# Phase 6: Complete Testing Protocol

**Project**: MegaLTR v2.0 - Final Validation
**Author**: Asmaa Boulhend
**Date**: 2026-01-15

---

## Executive Summary

This document provides a **step-by-step testing protocol** to validate that:

1. ✅ Nextflow workflow executes without errors
2. ✅ All processes complete successfully
3. ✅ Phase 5 TSV splitting produces zero empty files
4. ✅ Scientific outputs match Bash pipeline (equivalence)
5. ✅ Conda environment works correctly
6. ✅ HPC compatibility (SLURM test)

**Estimated Testing Time**: 3-4 hours for complete validation

---

## Prerequisites

### Required Files
```bash
# Verify all required files exist
ls -lh Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna    # Genome
ls -lh Data_for_test/Arabidopsis_thaliana.gff                # Annotation
ls -lh MegaLTR.clean.yml                                     # Conda env
ls -lh main.nf                                               # Workflow
ls -lh nextflow.config                                       # Config
```

### Software Requirements
```bash
# Check Nextflow
nextflow -version
# Expected: >= 21.04.0

# Check Conda
conda --version
# Expected: >= 4.x

# Check Java (required by Nextflow)
java -version
# Expected: >= 11

# Check Git
git --version
# Expected: Any recent version
```

---

## Testing Plan Overview

```
┌─────────────────────────────────────────────────────────┐
│ Phase 6 Testing Protocol                                │
├─────────────────────────────────────────────────────────┤
│ TEST 1: Syntax Validation (5 min)                      │
│   → Verify workflow compiles                            │
│                                                          │
│ TEST 2: Conda Environment Test (10 min)                │
│   → Verify all dependencies available                   │
│                                                          │
│ TEST 3: Workflow Dry Run (5 min)                       │
│   → Preview execution without running                   │
│                                                          │
│ TEST 4: Complete Workflow Execution (2-3 hours)        │
│   → Full Arabidopsis chr1 pipeline                      │
│                                                          │
│ TEST 5: Phase 5 Splitting Validation (5 min)           │
│   → Verify zero empty chunks                            │
│                                                          │
│ TEST 6: Scientific Equivalence Check (30 min)          │
│   → Compare outputs with Bash pipeline                  │
│                                                          │
│ TEST 7: Resume Capability Test (30 min)                │
│   → Simulate failure and resume                         │
│                                                          │
│ TEST 8: Resource Reports Review (10 min)               │
│   → Analyze timeline and resource usage                │
└─────────────────────────────────────────────────────────┘
```

---

## TEST 1: Syntax Validation (5 minutes)

### Objective
Verify Nextflow workflow compiles without syntax errors.

### Steps

**Step 1.1: Check workflow syntax**
```bash
cd /home/asmaa/MegaLTR

# Test help message
nextflow run main.nf --help
```

**Expected Output**:
```
==============================================================
MegaLTR Nextflow Pipeline v2.0
==============================================================

Usage:
  nextflow run main.nf --genome <genome.fna> [options]

Required arguments:
  --genome FILE           Input genome FASTA file
...
```

**✅ Pass Criteria**: Help message displays without errors

**Step 1.2: Validate configuration**
```bash
# Check config syntax
nextflow config -profile conda -show-profiles
```

**Expected Output**:
```
Available profiles:
  - standard
  - conda
  - docker
  - singularity
  - slurm
  - pbs
  - lsf
  - sge
  - awsbatch
  - test
```

**✅ Pass Criteria**: All profiles listed without errors

**Step 1.3: Validate input files**
```bash
# Check genome file
head -1 Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna
# Expected: >NC_003070.9 Arabidopsis thaliana chromosome 1...

# Check GFF file
head -1 Data_for_test/Arabidopsis_thaliana.gff
# Expected: ##gff-version 3

# Count sequences
grep -c '^>' Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna
# Expected: 1 (single chromosome)
```

**✅ Pass Criteria**: Files exist and have valid format

### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "Invalid UUID string: false" | Resume setting in config | Already fixed (removed resume=false) |
| "command not found: nextflow" | Nextflow not in PATH | `conda install -c bioconda nextflow` |
| "genome file not found" | Wrong path | Use absolute path or check current directory |

---

## TEST 2: Conda Environment Test (10 minutes)

### Objective
Verify Conda environment can be created and contains all required tools.

### Steps

**Step 2.1: Create/verify Conda environment**
```bash
# Create environment from YAML
conda env create -f MegaLTR.clean.yml -n MegaLTR_test

# Or if already exists, verify
conda activate MegaLTR
```

**Step 2.2: Verify critical tools**
```bash
# Activate environment
conda activate MegaLTR

# Check Python
python3 --version
# Expected: Python 3.x

# Check Perl
perl --version
# Expected: perl 5.x

# Check TEsorter
TEsorter -h 2>&1 | head -5
# Expected: TEsorter help message

# Check R
R --version
# Expected: R version 4.x

# Check ClustalW
clustalw -help 2>&1 | head -5
# Expected: ClustalW help

# Check GenomeTools
gt --version
# Expected: GenomeTools version

# Deactivate
conda deactivate
```

**✅ Pass Criteria**: All tools respond with version/help (no "command not found")

**Step 2.3: Verify Python scripts are executable**
```bash
# Check Phase 3 scripts
ls -lh bin/RUN/*.py

# Verify smart_split_tsv.py (Phase 5)
ls -lh bin/RUN/smart_split_tsv.py
# Expected: -rwxr-xr-x (executable)

# Test smart_split_tsv.py help
python3 bin/RUN/smart_split_tsv.py --help
# Expected: Usage message
```

**✅ Pass Criteria**: All .py files are executable, smart_split_tsv.py shows help

### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "CondaValueError: prefix already exists" | Environment exists | Use `conda env update` or delete first |
| "PackageNotFoundError" | Wrong channels | Check `channels:` in MegaLTR.clean.yml |
| "Permission denied" on .py | Not executable | `chmod +x bin/RUN/*.py` |

---

## TEST 3: Workflow Dry Run (5 minutes)

### Objective
Preview workflow execution without actually running processes.

### Steps

**Step 3.1: Preview with small dataset**
```bash
# Dry run (shows what would execute)
nextflow run main.nf \
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  --gff Data_for_test/Arabidopsis_thaliana.gff \
  --threads 2 \
  -preview
```

**Expected Output**:
```
==============================================================
MegaLTR Nextflow Pipeline - Starting
==============================================================
Genome       : Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna
GFF          : Data_for_test/Arabidopsis_thaliana.gff
Analysis Type: 3
Output       : megaltr_results
Prefix       : results
Threads      : 2
==============================================================

[-        ] PREPARE_GENOME             -
[-        ] PREPARE_TRNA               -
[-        ] PREPARE_GFF                -
[-        ] LTR_FINDER                 -
[-        ] LTR_HARVEST                -
[-        ] MERGE_LTR_CANDIDATES       -
[-        ] LTR_RETRIEVER              -
[-        ] LTRDIGEST                  -
[-        ] TESORTER                   -
[-        ] MERGE_RESULTS              -
[-        ] SPLIT_COORDINATES          -
[-        ] EXTRACT_SEQUENCES          -
[-        ] BUILD_NONREDUNDANT_LIBRARY -
[-        ] CALCULATE_INSERTION_TIME   -
[-        ] GENERATE_TIME_PLOTS        -
[-        ] IDENTIFY_GENE_CHIMERAS     -
[-        ] FIND_NEARBY_GENES          -
[-        ] VISUALIZE_CHROMOSOME_DENSITY -
[-        ] RESTORE_IDS                -
```

**✅ Pass Criteria**: All 18 processes listed, no errors

**Step 3.2: Check DAG generation**
```bash
# Generate workflow DAG
nextflow run main.nf \
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  --gff Data_for_test/Arabidopsis_thaliana.gff \
  -with-dag workflow_dag.html \
  -preview

# View DAG (open in browser)
ls -lh workflow_dag.html
```

**✅ Pass Criteria**: DAG file created, shows process dependencies

### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "No such file" for genome | Wrong path | Use absolute path or `pwd` to check location |
| "Analysis type 3 requires --gff" | Missing GFF for mode 3 | Add `--gff` parameter or use `--analysis_type 1` |
| Process list incomplete | Conditional logic issue | Check if `analysis_type` is set correctly |

---

## TEST 4: Complete Workflow Execution (2-3 hours)

### Objective
Run full MegaLTR pipeline end-to-end on Arabidopsis chr1.

### Steps

**Step 4.1: Clean previous runs (optional)**
```bash
# Remove old outputs
rm -rf megaltr_results/ work/ .nextflow/ .nextflow.log*

# Or keep work/ for resume testing
rm -rf megaltr_results/
```

**Step 4.2: Run complete workflow**
```bash
# Full execution with Conda profile
nextflow run main.nf \
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  --gff Data_for_test/Arabidopsis_thaliana.gff \
  --analysis_type 3 \
  --threads 4 \
  --outdir test_run_nextflow \
  -profile conda \
  -with-report test_run_nextflow/report.html \
  -with-timeline test_run_nextflow/timeline.html \
  -with-trace test_run_nextflow/trace.txt \
  -with-dag test_run_nextflow/dag.svg \
  2>&1 | tee test_run_nextflow.log
```

**Expected Progress** (monitor in terminal):
```
executor >  local (18)
[xx/xxxxxx] PREPARE_GENOME (1)           [100%] 1 of 1 ✔
[xx/xxxxxx] PREPARE_TRNA (1)             [100%] 1 of 1 ✔
[xx/xxxxxx] PREPARE_GFF (1)              [100%] 1 of 1 ✔
[xx/xxxxxx] LTR_FINDER (1)               [100%] 1 of 1 ✔
[xx/xxxxxx] LTR_HARVEST (1)              [100%] 1 of 1 ✔
[xx/xxxxxx] MERGE_LTR_CANDIDATES (1)     [100%] 1 of 1 ✔
[xx/xxxxxx] LTR_RETRIEVER (1)            [100%] 1 of 1 ✔
[xx/xxxxxx] LTRDIGEST (1)                [100%] 1 of 1 ✔
[xx/xxxxxx] TESORTER (1)                 [100%] 1 of 1 ✔
[xx/xxxxxx] MERGE_RESULTS (1)            [100%] 1 of 1 ✔
[xx/xxxxxx] SPLIT_COORDINATES (1)        [100%] 1 of 1 ✔
[xx/xxxxxx] EXTRACT_SEQUENCES (1)        [100%] 1 of 1 ✔
[xx/xxxxxx] BUILD_NONREDUNDANT_LIBRARY (1) [100%] 1 of 1 ✔
[xx/xxxxxx] CALCULATE_INSERTION_TIME (1) [100%] 1 of 1 ✔
[xx/xxxxxx] GENERATE_TIME_PLOTS (1)      [100%] 1 of 1 ✔
[xx/xxxxxx] IDENTIFY_GENE_CHIMERAS (1)   [100%] 1 of 1 ✔
[xx/xxxxxx] FIND_NEARBY_GENES (1)        [100%] 1 of 1 ✔
[xx/xxxxxx] VISUALIZE_CHROMOSOME_DENSITY (1) [100%] 1 of 1 ✔
[xx/xxxxxx] RESTORE_IDS (1)              [100%] 1 of 1 ✔

==============================================================
MegaLTR Pipeline Complete!
==============================================================
Status       : SUCCESS
Duration     : 2h 15m
Analysis Type: 3
Output Dir   : test_run_nextflow
==============================================================
```

**✅ Pass Criteria**:
- All processes show "✔" (completed)
- Status: SUCCESS
- No error messages in log

**Step 4.3: Check output files**
```bash
# List all outputs
ls -lh test_run_nextflow/results/

# Expected files
ls test_run_nextflow/results/*.{tsv,fa,fasta,png,svg} 2>/dev/null
```

**Expected Output Files**:
```
test_run_nextflow/results/
├── LTR_Table_TEsorter_Digest.tsv           # Main annotation table
├── results.statistics.tsv                   # Superfamily statistics
├── results.ids.extract_seq                  # Coordinates for extraction
├── LTR-RT_Sequence.fa                      # All LTR sequences
├── LTR-RTs_non-redundant_library.fasta     # Non-redundant library
├── results.Digest_TEsorter_Time.tsv        # With insertion times
├── *.png                                    # Time/length plots
├── LTR_Table_Digest_TEsorter_Time_nongene_and_gene.tsv  # Gene chimeras
├── results.genes_up_and_down_LTR.tsv       # Nearby genes
├── Gene density and LTR-RTs distribution.svg  # Chromosome plot
└── *.restored                               # Original IDs restored
```

**✅ Pass Criteria**: All key files exist and have non-zero size

### Monitoring During Execution

**Real-time progress**:
```bash
# In another terminal, monitor work directory
watch -n 5 'find work/ -name ".exitcode" | wc -l'
# Shows completed processes

# Check latest process output
tail -f .nextflow.log
```

**Check specific process**:
```bash
# Find work directory for specific process
find work/ -name ".command.log" -path "*/LTR_FINDER/*" | head -1
# Then read: cat <path>/.command.log
```

### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "Process LTR_FINDER failed" | Tool error | Check `work/XX/YYY/.command.log` |
| "Out of memory" | Insufficient RAM | Reduce `--threads` or increase `max_memory` |
| "Cannot find conda environment" | Conda issue | Run with `-profile conda` explicitly |
| "Process terminated by timeout" | Process too slow | Increase time limits in nextflow.config |

---

## TEST 5: Phase 5 Splitting Validation (5 minutes)

### Objective
Verify Phase 5 adaptive TSV splitting produces zero empty files.

### Steps

**Step 5.1: Find SPLIT_COORDINATES work directory**
```bash
# Find the work directory
SPLIT_DIR=$(find work/ -type d -name "*SPLIT_COORDINATES*" | head -1)
echo "SPLIT_COORDINATES directory: $SPLIT_DIR"

# Or find by looking for chunk files
CHUNK_DIR=$(find work/ -name "chunk*" -type f | head -1 | xargs dirname)
echo "Chunk directory: $CHUNK_DIR"
```

**Step 5.2: Count chunks created**
```bash
# Count chunk files
ls $CHUNK_DIR/chunk* 2>/dev/null | wc -l
# Expected for 39 LTRs with threads=4: 16 chunks
```

**Step 5.3: Verify ZERO empty chunks**
```bash
# Find empty chunks
find $CHUNK_DIR -name "chunk*" -empty

# Count empty chunks
EMPTY_COUNT=$(find $CHUNK_DIR -name "chunk*" -empty | wc -l)
echo "Empty chunks: $EMPTY_COUNT"
# Expected: 0
```

**✅ Pass Criteria**:
- Chunk count between 10-20 (adaptive)
- **ZERO empty chunks**

**Step 5.4: Verify all coordinates preserved**
```bash
# Count lines in original file
COORD_FILE=$(find test_run_nextflow/results -name "results.ids.extract_seq")
ORIGINAL_LINES=$(wc -l < $COORD_FILE)
echo "Original coordinates: $ORIGINAL_LINES"

# Count lines in all chunks
CHUNK_LINES=$(cat $CHUNK_DIR/chunk* | wc -l)
echo "Total in chunks: $CHUNK_LINES"

# Should be equal
if [ $ORIGINAL_LINES -eq $CHUNK_LINES ]; then
    echo "✅ All coordinates preserved"
else
    echo "❌ Coordinate mismatch!"
fi
```

**✅ Pass Criteria**: Original lines = Chunk lines (no loss)

**Step 5.5: Verify no duplicates**
```bash
# Check for duplicates
cat $CHUNK_DIR/chunk* | sort | uniq -d
# Expected: empty output (no duplicates)

# Count unique vs total
TOTAL=$(cat $CHUNK_DIR/chunk* | wc -l)
UNIQUE=$(cat $CHUNK_DIR/chunk* | sort -u | wc -l)

if [ $TOTAL -eq $UNIQUE ]; then
    echo "✅ No duplicates"
else
    echo "❌ Found duplicates: $((TOTAL - UNIQUE))"
fi
```

**✅ Pass Criteria**: No duplicate coordinates

### Expected Results

**For Arabidopsis chr1 (typical values)**:
```
LTR count: 39
Threads: 4
Adaptive chunk count: min(39, 4×4) = 16

Result:
- Chunks created: 16
- Empty chunks: 0
- Lines per chunk: 2-3
- Total lines: 39 (preserved)
- Duplicates: 0
```

**Comparison with Old Method**:
```
Old (split -n l/100):
- Chunks: 100 (fixed)
- Empty: 61 (61% waste)
- File reduction: 0%

New (smart_split_tsv.py):
- Chunks: 16 (adaptive)
- Empty: 0 (0% waste)
- File reduction: 84%
```

---

## TEST 6: Scientific Equivalence Check (30 minutes)

### Objective
Compare Nextflow outputs with Bash pipeline to verify identical results.

### Prerequisite
Run Bash pipeline first (if not already done):
```bash
# Run original Bash pipeline
conda activate MegaLTR
bash MegaLTR.sh \
  -A 3 \
  -F Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  -G Data_for_test/Arabidopsis_thaliana.gff \
  -P baseline \
  -t 4

# Outputs will be in: baseline/Collected_Files/
```

### Steps

**Step 6.1: Compare LTR counts**
```bash
# Bash pipeline LTR count
BASH_COUNT=$(wc -l < baseline/Collected_Files/LTR_Table_TEsorter_Digest.tsv)
echo "Bash LTR count: $BASH_COUNT"

# Nextflow pipeline LTR count
NF_COUNT=$(wc -l < test_run_nextflow/results/LTR_Table_TEsorter_Digest.tsv)
echo "Nextflow LTR count: $NF_COUNT"

# Compare
if [ $BASH_COUNT -eq $NF_COUNT ]; then
    echo "✅ LTR counts match"
else
    echo "❌ LTR count mismatch!"
fi
```

**Expected**: Both should detect same number of LTRs (~40 for Arabidopsis chr1)

**Step 6.2: Compare sequence counts**
```bash
# Bash sequence count
BASH_SEQ=$(grep -c '^>' baseline/Collected_Files/LTR-RT_Sequence.fa)
echo "Bash sequences: $BASH_SEQ"

# Nextflow sequence count
NF_SEQ=$(grep -c '^>' test_run_nextflow/results/LTR-RT_Sequence.fa)
echo "Nextflow sequences: $NF_SEQ"

# Compare
if [ $BASH_SEQ -eq $NF_SEQ ]; then
    echo "✅ Sequence counts match"
else
    echo "❌ Sequence count mismatch!"
fi
```

**Step 6.3: Compare library sizes**
```bash
# Bash library size
BASH_LIB=$(grep -c '^>' baseline/Collected_Files/LTR-RTs_non-redundant_library.fasta)
echo "Bash library: $BASH_LIB"

# Nextflow library size
NF_LIB=$(grep -c '^>' test_run_nextflow/results/LTR-RTs_non-redundant_library.fasta)
echo "Nextflow library: $NF_LIB"

# Compare
if [ $BASH_LIB -eq $NF_LIB ]; then
    echo "✅ Library sizes match"
else
    echo "❌ Library size mismatch!"
fi
```

**Step 6.4: Compare superfamily statistics**
```bash
# Compare statistics files
echo "Superfamily statistics comparison:"
diff -y --suppress-common-lines \
  baseline/Collected_Files/baseline.statistics.tsv \
  test_run_nextflow/results/results.statistics.tsv

# If empty output, files are identical
```

**✅ Pass Criteria**: No differences (or only header differences)

**Step 6.5: Compare LTR coordinates (sample)**
```bash
# Extract first 5 LTR coordinates from each
# Bash
head -6 baseline/Collected_Files/LTR_Table_TEsorter_Digest.tsv | tail -5 | \
  awk '{print $2,$3,$4,$5}' > bash_coords.txt

# Nextflow
head -6 test_run_nextflow/results/LTR_Table_TEsorter_Digest.tsv | tail -5 | \
  awk '{print $2,$3,$4,$5}' > nf_coords.txt

# Compare
echo "Coordinate comparison (first 5 LTRs):"
diff -y bash_coords.txt nf_coords.txt
```

**✅ Pass Criteria**: Identical coordinates (chr, start, end, length)

**Step 6.6: Compare superfamily classifications**
```bash
# Count Copia superfamily
BASH_COPIA=$(grep -c "Copia" baseline/Collected_Files/LTR_Table_TEsorter_Digest.tsv)
NF_COPIA=$(grep -c "Copia" test_run_nextflow/results/LTR_Table_TEsorter_Digest.tsv)

echo "Copia count - Bash: $BASH_COPIA, Nextflow: $NF_COPIA"

# Count Gypsy superfamily
BASH_GYPSY=$(grep -c "Gypsy" baseline/Collected_Files/LTR_Table_TEsorter_Digest.tsv)
NF_GYPSY=$(grep -c "Gypsy" test_run_nextflow/results/LTR_Table_TEsorter_Digest.tsv)

echo "Gypsy count - Bash: $BASH_GYPSY, Nextflow: $NF_GYPSY"

# Verify
if [ $BASH_COPIA -eq $NF_COPIA ] && [ $BASH_GYPSY -eq $NF_GYPSY ]; then
    echo "✅ Superfamily classifications match"
else
    echo "❌ Classification mismatch!"
fi
```

### Summary Report

Create a summary comparison:
```bash
cat > equivalence_report.txt << 'EOF'
=== Scientific Equivalence Report ===
Date: $(date)

Metric                  | Bash    | Nextflow | Match
------------------------|---------|----------|------
Total LTRs              | $BASH_COUNT | $NF_COUNT | $([ $BASH_COUNT -eq $NF_COUNT ] && echo "✅" || echo "❌")
Extracted sequences     | $BASH_SEQ | $NF_SEQ | $([ $BASH_SEQ -eq $NF_SEQ ] && echo "✅" || echo "❌")
Non-redundant library   | $BASH_LIB | $NF_LIB | $([ $BASH_LIB -eq $NF_LIB ] && echo "✅" || echo "❌")
Copia superfamily       | $BASH_COPIA | $NF_COPIA | $([ $BASH_COPIA -eq $NF_COPIA ] && echo "✅" || echo "❌")
Gypsy superfamily       | $BASH_GYPSY | $NF_GYPSY | $([ $BASH_GYPSY -eq $NF_GYPSY ] && echo "✅" || echo "❌")

Conclusion: $([ $BASH_COUNT -eq $NF_COUNT ] && echo "PASS - Scientific equivalence verified" || echo "FAIL - Investigate differences")
EOF

cat equivalence_report.txt
```

**✅ Overall Pass Criteria**: All metrics match (100% equivalence)

### Acceptable Differences

Some minor differences are acceptable:
- **File order**: Bash vs Nextflow may order outputs differently (use `sort` to compare)
- **Floating point**: Insertion time estimates may differ by ±0.01 Ma (rounding)
- **Timestamps**: File creation times will differ
- **ID format**: If original IDs differ, but restored IDs should match

**NOT acceptable**:
- Different LTR counts
- Different coordinates
- Different superfamily classifications
- Different library sizes

---

## TEST 7: Resume Capability Test (30 minutes)

### Objective
Verify `-resume` works correctly after simulated failure.

### Steps

**Step 7.1: Simulate a failure**
```bash
# Modify TESORTER process to fail (temporarily)
# Edit main.nf, add exit 1 to TESORTER script

# Or kill workflow mid-execution
nextflow run main.nf \
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  --gff Data_for_test/Arabidopsis_thaliana.gff \
  --outdir test_resume \
  -profile conda &

# After LTR_RETRIEVER completes, kill it
sleep 1800  # Wait 30 min
pkill -f nextflow
```

**Step 7.2: Check what completed**
```bash
# Count completed processes
find work/ -name ".exitcode" -exec cat {} \; | grep -c "^0$"
# This shows how many processes completed successfully

# List completed processes
find work/ -name ".command.sh" | while read cmd; do
  dir=$(dirname $cmd)
  if [ -f "$dir/.exitcode" ] && [ "$(cat $dir/.exitcode)" = "0" ]; then
    grep "^\[" $dir/.command.log | head -1
  fi
done
```

**Step 7.3: Resume execution**
```bash
# Resume from last checkpoint
nextflow run main.nf \
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  --gff Data_for_test/Arabidopsis_thaliana.gff \
  --outdir test_resume \
  -profile conda \
  -resume \
  2>&1 | tee resume.log
```

**Expected Output**:
```
executor >  local (10)
[xx/xxxxxx] PREPARE_GENOME (1)           [100%] 1 of 1, cached: 1 ✔
[xx/xxxxxx] PREPARE_TRNA (1)             [100%] 1 of 1, cached: 1 ✔
[xx/xxxxxx] LTR_FINDER (1)               [100%] 1 of 1, cached: 1 ✔
[xx/xxxxxx] LTR_HARVEST (1)              [100%] 1 of 1, cached: 1 ✔
[xx/xxxxxx] LTR_RETRIEVER (1)            [100%] 1 of 1, cached: 1 ✔
...
[xx/xxxxxx] TESORTER (1)                 [100%] 1 of 1 ✔  ← Re-executed
[xx/xxxxxx] MERGE_RESULTS (1)            [100%] 1 of 1 ✔  ← New
...
```

**✅ Pass Criteria**:
- Completed processes show "cached: 1"
- Only failed/downstream processes re-execute
- Much faster runtime (skips completed work)

**Step 7.4: Verify cache usage**
```bash
# Count cached processes
grep "cached:" resume.log | wc -l
# Should be > 0

# Calculate time saved
FULL_TIME=$(grep "Duration" test_run_nextflow.log | awk '{print $3}')
RESUME_TIME=$(grep "Duration" resume.log | awk '{print $3}')

echo "Full run: $FULL_TIME"
echo "Resume run: $RESUME_TIME"
echo "Time saved by resume: ~$(($(echo $FULL_TIME | sed 's/h.*//') - $(echo $RESUME_TIME | sed 's/h.*//')))h"
```

**✅ Pass Criteria**: Resume is significantly faster (>50% time saved)

---

## TEST 8: Resource Reports Review (10 minutes)

### Objective
Analyze execution reports to understand resource usage.

### Steps

**Step 8.1: View Timeline Report**
```bash
# Open timeline in browser
xdg-open test_run_nextflow/timeline.html
# Or on Mac: open test_run_nextflow/timeline.html
```

**What to look for**:
- **Gantt chart**: Shows which processes ran in parallel
- **Bottlenecks**: Identify longest-running processes
- **Idle time**: Gaps indicate serial execution (expected for dependencies)

**Expected observations**:
- LTR_FINDER and LTR_HARVEST should overlap (parallel)
- SPLIT_COORDINATES should be very fast (<1 min)
- LTR_RETRIEVER typically longest process (~1-2 hours)

**Step 8.2: View Resource Report**
```bash
# Open resource report
xdg-open test_run_nextflow/report.html
```

**What to look for**:
- **CPU efficiency**: % of requested CPUs actually used
- **Memory usage**: Peak vs requested
- **Under-allocated**: Process used more than requested (increase limits)
- **Over-allocated**: Process used much less (decrease limits)

**Expected findings**:
```
Process               | CPU Req | CPU Used | Efficiency
----------------------|---------|----------|------------
LTR_FINDER            | 4       | 3.8      | 95% (good)
LTR_HARVEST           | 4       | 3.9      | 97% (good)
PREPARE_GENOME        | 1       | 0.8      | 80% (acceptable)
SPLIT_COORDINATES     | 1       | 0.3      | 30% (expected, fast task)
```

**Step 8.3: Analyze Trace File**
```bash
# View trace as table
column -t -s $'\t' test_run_nextflow/trace.txt | less -S

# Find slowest processes
sort -t$'\t' -k5 -rn test_run_nextflow/trace.txt | head -5 | \
  awk -F'\t' '{print $4, $5}'
# Column 4 = process name, Column 5 = duration

# Find memory hogs
sort -t$'\t' -k13 -rn test_run_nextflow/trace.txt | head -5 | \
  awk -F'\t' '{print $4, $13}'
# Column 13 = peak memory
```

**Step 8.4: Review DAG**
```bash
# View workflow DAG
xdg-open test_run_nextflow/dag.svg
```

**What to verify**:
- All 18 processes present
- Correct dependencies (arrows)
- SPLIT_COORDINATES → EXTRACT_SEQUENCES connection visible
- Conditional branches (analysis_type >=2, >=3) shown

**✅ Pass Criteria**:
- Reports generate without errors
- No process exceeded resource limits
- Parallelism visible in timeline

---

## TEST 9: Quick HPC Compatibility Check (Optional, 15 min)

### Objective
Verify SLURM profile works (if HPC available).

### Prerequisites
- Access to SLURM cluster
- MegaLTR repository on shared filesystem

### Steps

**Step 9.1: Test SLURM profile syntax**
```bash
# On HPC login node
cd /path/to/MegaLTR

# Test config
nextflow config -profile slurm,conda
```

**Step 9.2: Submit small test job**
```bash
# Run with SLURM profile (dry run first)
nextflow run main.nf \
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  --gff Data_for_test/Arabidopsis_thaliana.gff \
  --analysis_type 1 \
  --threads 4 \
  -profile slurm,conda \
  -preview
```

**Step 9.3: Check job submission**
```bash
# Actual run (analysis_type 1 = faster)
nextflow run main.nf \
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
  --gff Data_for_test/Arabidopsis_thaliana.gff \
  --analysis_type 1 \
  --threads 4 \
  -profile slurm,conda

# In another terminal, check SLURM queue
watch -n 10 'squeue -u $USER'
```

**Expected**: Jobs appear in queue with names like `nf-LTR_FINDER`, `nf-LTR_HARVEST`, etc.

**✅ Pass Criteria**: Jobs submit successfully, processes complete

---

## Comprehensive Test Summary Template

After completing all tests, fill out this summary:

```markdown
# MegaLTR Phase 6 Testing Summary

**Date**: [DATE]
**Tester**: Asmaa Boulhend
**Nextflow Version**: [VERSION]
**Conda Version**: [VERSION]

## Test Results

| Test | Status | Notes |
|------|--------|-------|
| 1. Syntax Validation | ✅/❌ | |
| 2. Conda Environment | ✅/❌ | |
| 3. Workflow Dry Run | ✅/❌ | |
| 4. Complete Execution | ✅/❌ | Duration: __h __m |
| 5. Phase 5 Splitting | ✅/❌ | Chunks: __, Empty: __ |
| 6. Scientific Equivalence | ✅/❌ | LTR count match: ✅/❌ |
| 7. Resume Capability | ✅/❌ | Time saved: __% |
| 8. Resource Reports | ✅/❌ | |
| 9. HPC Compatibility | ✅/❌/N/A | |

## Key Metrics

- **Total LTRs detected**: [NUMBER]
- **Nextflow runtime**: [TIME]
- **Bash runtime** (baseline): [TIME]
- **Chunk count** (Phase 5): [NUMBER]
- **Empty chunks**: [NUMBER] (should be 0)
- **Scientific equivalence**: [PASS/FAIL]

## Issues Found

[List any issues, or write "None"]

## Recommendations

[Any recommendations for optimization]

## Conclusion

☐ **PASS** - All tests successful, ready for deployment
☐ **CONDITIONAL PASS** - Minor issues, acceptable for use
☐ **FAIL** - Critical issues must be resolved
```

---

## Troubleshooting Guide

### Common Issues and Solutions

**Issue**: "Cannot find conda environment"
**Solution**:
```bash
conda env create -f MegaLTR.clean.yml
nextflow run main.nf ... -profile conda
```

**Issue**: "Out of memory" during LTR_RETRIEVER
**Solution**:
```bash
# Edit nextflow.config, increase memory
withName: 'LTR_RETRIEVER' {
    memory = '64.GB'  # Increase from 32GB
}
```

**Issue**: "Process timeout"
**Solution**:
```bash
# Increase time limit
withName: 'LTR_FINDER' {
    time = '24.h'  # Increase from 12h
}
```

**Issue**: "smart_split_tsv.py: command not found"
**Solution**:
```bash
chmod +x bin/RUN/smart_split_tsv.py
# Verify it exists
ls -lh bin/RUN/smart_split_tsv.py
```

**Issue**: LTR counts don't match Bash pipeline
**Solution**:
```bash
# Check if same parameters used
grep "similarity\|min_ltr" main.nf
grep "similar\|minlenltr" MegaLTR.sh

# Verify same tools (conda versions)
conda activate MegaLTR
which TEsorter
TEsorter --version
```

**Issue**: Resume not working
**Solution**:
```bash
# Check if work/ directory exists
ls -ld work/

# Verify no parameters changed
# (changing params invalidates cache)

# Try with -resume flag explicitly
nextflow run main.nf ... -resume
```

---

## Final Checklist

Before concluding the project, verify:

- [ ] All 8 tests passed (or acceptable conditional pass)
- [ ] Scientific equivalence confirmed (LTR counts match)
- [ ] Phase 5 splitting validated (zero empty chunks)
- [ ] Documentation complete (3 docs created)
- [ ] Git commits pushed to branch
- [ ] Ready for supervisor presentation

---

## Next Steps After Testing

**If all tests PASS**:
1. Create pull request to merge `feat/nextflow-migration` to `main`
2. Tag release as `v2.0.0`
3. Write final project report
4. Prepare presentation for supervisor

**If tests FAIL**:
1. Document specific failures in issues
2. Debug using work directory logs
3. Fix issues and re-test
4. Do NOT proceed until critical issues resolved

---

**Document Version**: 1.0
**Author**: Asmaa Boulhend
**Date**: 2026-01-15
**Purpose**: Complete validation before project conclusion
