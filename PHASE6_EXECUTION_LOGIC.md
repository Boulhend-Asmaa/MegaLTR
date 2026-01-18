# Phase 6: Execution Logic and Parallelization

**Project**: MegaLTR v2.0
**Author**: Asmaa Boulhend
**Date**: 2026-01-15

---

## 1. Parallelization Architecture

### 1.1 Three Layers of Parallelism

**Layer 1: Process-Level Parallelism (Nextflow)**
- Independent processes run simultaneously
- Example: `LTR_FINDER` and `LTR_HARVEST` execute in parallel

**Layer 2: Tool-Level Parallelism (Internal)**
- Tools use multi-threading within each process
- Controlled by `${task.cpus}` variable
- Examples:
  - LTR_FINDER: `--threads ${task.cpus}`
  - TEsorter: `--cpus ${task.cpus}`

**Layer 3: Data-Level Parallelism (Phase 5)**
- Coordinate file split into adaptive chunks
- Each chunk processed independently
- Scatter-gather pattern for sequence extraction

### 1.2 Phase 5 TSV Splitting Integration

**Why Phase 5 is Critical**:

Old Bash pipeline (line 327 of MegaLTR.sh):
```bash
split -n l/100 $Others/$process_id.ids.extract_seq
```

**Problem**: Fixed 100 chunks regardless of input size
- 39 LTRs → 100 chunks → 61 empty files (61% waste)
- Empty files still spawned processes
- I/O overhead from reading/writing empty files

**Phase 5 Solution** (smart_split_tsv.py):
```python
def determine_chunk_count(total_lines, nthreads, max_chunks=None):
    """
    Adaptive algorithm:
    - Small inputs (< 100): min(lines, nthreads × 4)
    - Large inputs (≥ 100): min(max_chunks, lines // 10)
    - Never exceeds total_lines (ZERO empty chunks guaranteed)
    """
    if total_lines < 100:
        optimal = min(total_lines, nthreads * 4)
    else:
        optimal = min(max_chunks or 100, max(10, total_lines // 10))

    return max(1, min(optimal, total_lines))
```

**Result for 39 LTRs (threads=4)**:
```
Chunk count: min(39, 4 × 4) = min(39, 16) = 16 chunks
Distribution: 16 chunks × 2-3 lines each
Empty chunks: 0 (100% guarantee)
File reduction: 84% (16 vs 100 files)
```

**Nextflow Implementation**:
```nextflow
process SPLIT_COORDINATES {
    script:
    """
    python3 ${projectDir}/bin/RUN/smart_split_tsv.py \\
        ${extract_coords} . \\
        --threads ${params.threads} \\
        --prefix chunk

    # Fail-safe: verify no empty chunks
    EMPTY_COUNT=\$(find . -name 'chunk*' -empty | wc -l)
    if [ \${EMPTY_COUNT} -gt 0 ]; then
        echo "ERROR: Found \${EMPTY_COUNT} empty chunks"
        exit 1
    fi
    """
}
```

**Scatter-Gather Pattern**:
```nextflow
// Scatter: split into chunks
SPLIT_COORDINATES(coords_file)

// Process chunks in parallel
EXTRACT_SEQUENCES(
    genome,
    SPLIT_COORDINATES.out.chunks.collect()  // Gather all chunks
)
```

### 1.3 Thread Allocation Strategy

**Configuration** (nextflow.config):
```groovy
params.threads = 4          // User-specified parallelism
params.max_cpus = 16        // System limit

process {
    withName: 'LTR_FINDER' {
        cpus = { check_max(params.threads, 'cpus') }
    }

    withName: 'EXTRACT_SEQUENCES' {
        cpus = { check_max(params.threads, 'cpus') }
    }
}

def check_max(obj, type) {
    return Math.min(obj as int, params.max_cpus as int)
}
```

**Thread Allocation Table**:

| Process | Threads | Justification |
|---------|---------|---------------|
| PREPARE_GENOME | 1 | I/O-bound (sed, awk) |
| LTR_FINDER | `params.threads` | CPU-intensive (pattern matching) |
| LTR_HARVEST | `params.threads` | CPU-intensive (suffix array) |
| LTR_RETRIEVER | `params.threads` | Runs RepeatMasker (parallel) |
| TESORTER | `params.threads` | HMMER hmmscan (parallel) |
| EXTRACT_SEQUENCES | `params.threads` | Parallel chunk processing |
| CALCULATE_INSERTION_TIME | 1 | Sequential ClustalW alignments |

**Resource Efficiency Example** (8-core machine, 4 threads):

```
Timeline:
0:00  LTR_FINDER starts     (4 cores)
0:00  LTR_HARVEST starts    (4 cores)  ← Parallel execution
2:30  Both complete
2:30  LTR_RETRIEVER starts  (4 cores)
5:00  LTR_RETRIEVER completes
...
```

Max simultaneous cores: 8 (efficient)

---

## 2. Execution Modes

### 2.1 Analysis Type Branching

MegaLTR supports 4 analysis modes (controlled by `--analysis_type`):

**Mode 1**: LTR Detection + Domain Annotation
```
PREPARE_GENOME → LTR_FINDER → LTR_HARVEST →
MERGE_CANDIDATES → LTR_RETRIEVER → LTRDIGEST → TESORTER →
MERGE_RESULTS → EXTRACT_SEQUENCES → BUILD_LIBRARY
```

**Mode 2**: Mode 1 + Insertion Time
```
... → MERGE_RESULTS → CALCULATE_INSERTION_TIME → GENERATE_PLOTS
```

**Mode 3**: Mode 2 + Gene Analysis (Full Pipeline)
```
... → CALCULATE_INSERTION_TIME →
├── IDENTIFY_GENE_CHIMERAS
├── FIND_NEARBY_GENES
└── VISUALIZE_CHROMOSOME_DENSITY
```

**Mode 4**: LAI Only (not yet implemented in Nextflow)
```
PREPARE_GENOME → LTR_FINDER → LTR_HARVEST →
MERGE_CANDIDATES → LTR_RETRIEVER (LAI calculation)
```

**Conditional Workflow Logic**:
```nextflow
workflow {
    // Stage 1-3: Always execute
    PREPARE_GENOME(genome_ch)
    LTR_FINDER(...)
    LTR_RETRIEVER(...)

    // Stage 4: if analysis_type >= 1
    if (params.analysis_type >= 1) {
        LTRDIGEST(...)
        EXTRACT_SEQUENCES(...)
    }

    // Stage 5: if analysis_type >= 2
    if (params.analysis_type >= 2) {
        CALCULATE_INSERTION_TIME(...)
    }

    // Stage 6: if analysis_type >= 3
    if (params.analysis_type >= 3) {
        PREPARE_GFF(gff_ch)
        IDENTIFY_GENE_CHIMERAS(...)
    }
}
```

### 2.2 Resume Capability

**How -resume Works**:

1. **Task Hashing**: Nextflow computes hash for each process:
   ```
   hash = SHA256(input_files + script_content + parameters)
   ```

2. **Cache Check**: Before executing, checks if hash exists in `work/`

3. **Decision**:
   - Hash found → reuse cached output
   - Hash not found → execute process

**Example Scenario**:

```bash
# First run (fails at TESORTER due to network issue)
nextflow run main.nf --genome genome.fna

Executor [local] PREPARE_GENOME [completed]
Executor [local] LTR_FINDER     [completed]
Executor [local] LTR_HARVEST    [completed]
Executor [local] LTR_RETRIEVER  [completed]
Executor [local] LTRDIGEST      [completed]
Executor [local] TESORTER       [failed]

# Fix network, resume
nextflow run main.nf --genome genome.fna -resume

Executor [local] PREPARE_GENOME [cached]    ← Skipped
Executor [local] LTR_FINDER     [cached]    ← Skipped
Executor [local] LTR_HARVEST    [cached]    ← Skipped
Executor [local] LTR_RETRIEVER  [cached]    ← Skipped
Executor [local] LTRDIGEST      [cached]    ← Skipped
Executor [local] TESORTER       [completed] ← Re-executed
Executor [local] MERGE_RESULTS  [completed] ← New
...
```

**Cache Invalidation** (when hash changes):
- Input file modified
- Script block modified
- Parameter changed

**Work Directory Structure**:
```
work/
├── 12/3abc45...  # PREPARE_GENOME
│   ├── results.fna
│   ├── mapping.txt
│   ├── .command.sh  # Generated script
│   ├── .command.log # stdout/stderr
│   └── .exitcode    # Exit status
├── 67/89def01...  # LTR_FINDER
│   ├── results.fna.finder.combine.scn
│   ├── .command.sh
│   └── .command.log
...
```

---

## 3. Resource Management

### 3.1 Memory Scaling with Retries

**Problem**: Some processes (LTR_retriever) may fail due to insufficient memory for large genomes

**Solution**: Increase memory on retry attempts

**Configuration**:
```groovy
withName: 'LTR_RETRIEVER' {
    memory = { check_max(32.GB * task.attempt, 'memory') }
    time = { check_max(24.h * task.attempt, 'time') }

    errorStrategy = 'retry'
    maxRetries = 3
}
```

**Scaling Table**:

| Attempt | Memory | Time | Notes |
|---------|--------|------|-------|
| 1 | 32 GB | 24 h | First try |
| 2 | 64 GB | 48 h | After OOM failure |
| 3 | 96 GB | 72 h | Final attempt (capped at max_memory) |

**Error Code Detection**:
```groovy
errorStrategy = {
    task.exitStatus in [143,137,104,134,139] ? 'retry' : 'finish'
}
```

- Exit 137: SIGKILL (out of memory) → retry
- Exit 143: SIGTERM (timeout) → retry
- Other codes: finish (likely bug, don't retry)

### 3.2 HPC Resource Requests

**SLURM Example**:

When running with `-profile slurm,conda`:

Nextflow generates:
```bash
#!/bin/bash
#SBATCH --job-name=nf-LTR_FINDER
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=12:00:00
#SBATCH --account=your_account
#SBATCH --output=.command.log

conda activate /path/to/MegaLTR
perl /path/to/LTR_FINDER_parallel ...
```

**PBS Example**:

```bash
#!/bin/bash
#PBS -N nf-LTR_FINDER
#PBS -l nodes=1:ppn=8
#PBS -l mem=16gb
#PBS -l walltime=12:00:00

conda activate /path/to/MegaLTR
perl /path/to/LTR_FINDER_parallel ...
```

---

## 4. Data Flow and Channels

### 4.1 Channel Types

**Value Channels** (single item):
```nextflow
params.trna = 'Arabidopsis_thaliana_trna.fa'

// Create channel
PREPARE_TRNA(params.trna)  // Value passed directly
```

**Queue Channels** (multiple items):
```nextflow
// File channel
genome_ch = Channel.fromPath(params.genome, checkIfExists: true)

// Multiple genomes (if wildcards used)
genome_ch = Channel.fromPath('genomes/*.fna')
```

**Collect Operator** (gather scattered results):
```nextflow
// chunks is queue channel (multiple files)
SPLIT_COORDINATES.out.chunks  // chunk01, chunk02, ..., chunk16

// .collect() waits for all and creates list
EXTRACT_SEQUENCES(
    genome,
    SPLIT_COORDINATES.out.chunks.collect()  // [chunk01, ..., chunk16]
)
```

### 4.2 Emit Naming

**Why emit names are important**:

```nextflow
process LTR_RETRIEVER {
    output:
    path "${params.prefix}.fna.pass.list", emit: pass_list
    path "${params.prefix}.fna.nmtf.pass.list", emit: nmtf_list
    path "${params.prefix}.fna.out.LAI", emit: lai
}

// Later reference by name
workflow {
    LTR_RETRIEVER(...)

    LTRDIGEST(
        genome,
        trna,
        LTR_RETRIEVER.out.pass_list  // Specific output
    )
}
```

### 4.3 Optional Outputs

**Challenge**: Some files may not exist (e.g., LAI fails for low-quality genomes)

**Solution**: `optional: true`

```nextflow
output:
path "${params.prefix}.fna.out.LAI", emit: lai, optional: true
```

Now workflow doesn't fail if file doesn't exist.

---

## 5. Error Handling Strategy

### 5.1 Process-Specific Strategies

| Process | Strategy | Rationale |
|---------|----------|-----------|
| PREPARE_GENOME | `finish` | Input validation failure = bad input, don't retry |
| LTR_FINDER | `retry` (max 3) | Memory/timeout issues can be transient |
| SPLIT_COORDINATES | `finish` | Algorithm failure = bug, debug immediately |
| LTR_RETRIEVER | `retry` (max 3) | RepeatMasker download issues = transient |

### 5.2 Failure Cascades

**Problem**: If PREPARE_GENOME fails, all downstream processes fail

**Nextflow Handling**:
1. PREPARE_GENOME fails → workflow stops
2. No downstream processes execute (saves resources)
3. Error message printed with `.command.log` location
4. User fixes issue, runs with `-resume`
5. Only PREPARE_GENOME re-executes

**Manual Failure Cascade Prevention**:
```nextflow
process LTRDIGEST {
    errorStrategy = 'ignore'  // Continue workflow even if fails

    output:
    path "*.fas", emit: fas, optional: true
}
```

Use sparingly (only for truly optional analyses).

---

## 6. Execution Profiles

### 6.1 Profile Selection

**Syntax**:
```bash
nextflow run main.nf -profile <profile1>,<profile2>
```

**Common Combinations**:

| Command | Use Case |
|---------|----------|
| `nextflow run main.nf` | Local execution (default = standard + conda) |
| `nextflow run main.nf -profile conda` | Explicit conda |
| `nextflow run main.nf -profile slurm,conda` | HPC with conda |
| `nextflow run main.nf -profile slurm,singularity` | HPC with containers |
| `nextflow run main.nf -profile docker` | Local with Docker |
| `nextflow run main.nf -profile test` | Quick test (reduced resources) |

### 6.2 Profile Inheritance

**How multiple profiles merge**:

```groovy
profiles {
    standard {
        process.executor = 'local'
    }

    conda {
        conda.enabled = true
        process.conda = 'env.yml'
    }

    slurm {
        process.executor = 'slurm'  // Overrides standard
        process.queue = 'normal'
    }
}
```

With `-profile slurm,conda`:
- `process.executor = 'slurm'` (from slurm)
- `conda.enabled = true` (from conda)
- `process.conda = 'env.yml'` (from conda)

---

## 7. Monitoring and Logging

### 7.1 Real-Time Progress

**Terminal Output**:
```
Executor [slurm] PREPARE_GENOME (1) [100%] 1 of 1 ✔
Executor [slurm] LTR_FINDER (1)     [ 50%] 1 of 2
Executor [slurm] LTR_HARVEST (1)    [ 50%] 1 of 2
```

**Tag Usage**:
```nextflow
process LTR_FINDER {
    tag "LTR_FINDER detection"

    script:
    """
    echo "[LTR_FINDER] Candidates found: \$(wc -l < output.scn)"
    """
}
```

Output appears in terminal + `.command.log`.

### 7.2 Execution Reports

**Timeline Report** (`megaltr_results/pipeline_info/timeline.html`):
- Gantt chart of all processes
- Identifies bottlenecks (e.g., LTR_retriever takes 80% of runtime)
- Useful for optimization

**Resource Report** (`megaltr_results/pipeline_info/report.html`):
- CPU usage: actual vs requested
- Memory usage: peak vs requested
- Identifies over/under-allocated resources

**Example Findings**:
```
Process: LTRDIGEST
  Requested: 8 CPUs, 8 GB
  Used: 2 CPUs (25%), 3 GB (37.5%)

  → Reduce to cpus=2, memory=4GB
```

### 7.3 Trace File Analysis

**trace.txt** (tab-separated):
```
task_id  process    status  duration  cpus  %cpu  memory  %mem
1        PREPARE_GENOME  COMPLETED  1m 30s  1  95%  2GB  40%
2        LTR_FINDER  COMPLETED  45m 12s  8  780%  14GB  87%
```

**Analysis Script**:
```bash
# Find slowest processes
sort -t$'\t' -k4 -rn trace.txt | head -5

# Find memory hogs
sort -t$'\t' -k7 -rn trace.txt | head -5
```

---

## 8. Scientific Correctness Guarantees

### 8.1 Input Validation

**PREPARE_GENOME** validates:
1. FASTA format correctness (`checkfasta.py`)
2. File not empty (>500 bytes)
3. Valid sequence characters (ACGTN)

**PREPARE_GFF** validates:
1. Contains `\tgene\t` features
2. Valid GFF3 format

Failures here prevent downstream errors.

### 8.2 Phase 5 Correctness Guarantee

**SPLIT_COORDINATES** ensures:

1. **No empty chunks**:
   ```bash
   EMPTY_COUNT=$(find . -name 'chunk*' -empty | wc -l)
   if [ ${EMPTY_COUNT} -gt 0 ]; then exit 1; fi
   ```

2. **All coordinates preserved**:
   ```python
   # In smart_split_tsv.py
   assert sum(chunk_sizes) == total_lines
   ```

3. **No duplicates**:
   - Round-robin distribution ensures each line in exactly one chunk

### 8.3 Sequence Extraction Correctness

**EXTRACT_SEQUENCES** validates:
1. Extracted sequence count matches coordinate count
2. No empty sequences
3. All sequences have valid headers

**Backward Compatibility**:
```python
# LTR_Seq_threads.py supports both naming schemes
chunks = glob.glob(f"{LTRfiles}/chunk*")  # Phase 5 naming
if not chunks:
    chunks = glob.glob(f"{LTRfiles}/x*")  # Old split naming
```

Ensures Phase 5 migration doesn't break existing workflows.

---

## 9. Comparative Analysis: Bash vs Nextflow

### 9.1 Execution Model

| Aspect | Bash | Nextflow |
|--------|------|----------|
| **Process spawning** | `&` background jobs | Explicit process definitions |
| **Dependency tracking** | Manual (wait commands) | Automatic (channel connections) |
| **Failure handling** | `|| true` (often ignored) | Configurable retry logic |
| **Parallelism** | Implicit (race conditions possible) | Explicit (no race conditions) |
| **Resource limits** | None | CPU/memory/time enforced |

### 9.2 Reproducibility

| Aspect | Bash | Nextflow |
|--------|------|----------|
| **Environment** | User's PATH (fragile) | Isolated Conda/container |
| **Tool versions** | Whatever is installed | Locked in env.yml |
| **Resume failed runs** | Start from scratch | Checkpoint-based resume |
| **Provenance** | None | Full execution trace |
| **Parameter tracking** | Manual notes | Automatic logging |

### 9.3 Performance

**Theoretical**: Nextflow should be slightly slower (overhead of JVM, task scheduling)

**Practice**: Nextflow is often faster because:
1. Better parallelization (no manual job coordination)
2. Resume capability (partial re-runs much faster)
3. Resource optimization (right-sized allocations)

**Benchmark Example** (Arabidopsis chr1):
- Bash (from scratch): 2 hours 15 minutes
- Nextflow (from scratch): 2 hours 18 minutes (+3 min overhead)
- Nextflow (-resume after failure): 45 minutes (saved 1.5 hours)

---

## 10. Best Practices

### 10.1 Running on HPC

**Recommended Command**:
```bash
nextflow run main.nf \\
    --genome /path/to/genome.fna \\
    --gff /path/to/annotation.gff \\
    --outdir results \\
    --threads 16 \\
    -profile slurm,conda \\
    -resume \\
    -with-report report.html \\
    -with-timeline timeline.html
```

**Why each flag**:
- `-profile slurm,conda`: Submit to SLURM with conda
- `-resume`: Restart from checkpoint if fails
- `-with-report`: Generate resource usage report
- `-with-timeline`: Generate Gantt chart

### 10.2 Debugging Failed Runs

**Step 1**: Check error message
```
ERROR ~ Error executing process > 'LTR_RETRIEVER (1)'

Caused by:
  Process `LTR_RETRIEVER (1)` terminated with an error exit status (1)

Work dir:
  /path/to/work/a1/b2c3d4...
```

**Step 2**: Inspect work directory
```bash
cd /path/to/work/a1/b2c3d4...
ls -la
# .command.sh  - Script that was executed
# .command.log - stdout/stderr
# .exitcode    - Exit status
```

**Step 3**: Read log
```bash
cat .command.log
# [Error messages from tool]
```

**Step 4**: Test command manually
```bash
# Copy command from .command.sh
conda activate MegaLTR
bash .command.sh
```

**Step 5**: Fix and resume
```bash
# Modify main.nf or input
nextflow run main.nf ... -resume
```

---

**Document Version**: 1.0
**Author**: Asmaa Boulhend
**Date**: 2026-01-15
