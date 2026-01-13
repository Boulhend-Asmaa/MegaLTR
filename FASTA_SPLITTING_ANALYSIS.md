# FASTA Splitting Analysis and Optimization

**Date**: 2026-01-13
**Author**: Asmaa Boulhend
**Project**: MegaLTR Pipeline Optimization

---

## Executive Summary

The current FASTA splitting implementation in MegaLTR has **critical inefficiencies** that create **61% empty files** and waste computational resources. This analysis documents the problems and proposes a robust, FASTA-aware splitting strategy.

**Key Findings**:
- Current implementation uses GNU `split -n l/100` (line-based splitting)
- Creates **100 fixed chunks** regardless of input size
- Test case: 39 LTR elements → 100 chunks → **61 empty files** (61% waste)
- Empty chunks cause unnecessary I/O, process spawning, and validation overhead
- Not FASTA-aware (works only because input is tab-delimited, not FASTA)

---

## 1. Current Implementation Analysis

### 1.1 Two Splitting Mechanisms Identified

#### Mechanism A: LTR_HARVEST_parallel (Genome FASTA Splitting)

**Location**: `bin/LTR_HARVEST_parallel/LTR_HARVEST_parallel` (line 139)

**Implementation**:
```perl
perl $cut ../$seq_file -s -l $size_of_each_piece
```

**Splitting script**: `bin/LTR_HARVEST_parallel/bin/cut.pl`

**Strategy**:
- FASTA-record aware ✅
- Splits by sequence size (default: 5 Mb chunks)
- Creates one file per chunk: `${genome}_sub1`, `${genome}_sub2`, etc.
- Creates manifest: `${genome}.list`

**Analysis**:
```perl
# cut.pl lines 18-46
$/="\n>";  # Set record separator to FASTA entry
while (<Seq>){
    s/>//g;
    my ($id, $seq)=(split /\n/, $_, 2);
    $seq=~s/\s+//g;

    # Split sequence into fixed-size chunks
    for (my $i=0; ; $i+=$len){
        my $seq_sub=substr($seq, $i, $len);
        print File ">${id}_sub$j\n$seq_sub\n";
    }
}
```

**Behavior**:
- Reads FASTA correctly (record-aware)
- Splits **within sequences** (breaks contigs/chromosomes)
- Each chunk gets a unique ID: `Chr1_sub1`, `Chr1_sub2`, etc.
- Coordinate adjustment handled in LTR_HARVEST_parallel (line 201-223)

**Assessment**: ✅ Biologically valid for LTR detection (LTRs are local features)

---

#### Mechanism B: LTR Extraction Coordinate Splitting (CRITICAL BUG)

**Location**: `MegaLTR.sh` (line 337)

**Implementation**:
```bash
split -n l/100 $Others/$process_id.ids.extract_seq
```

**Input file format** (`$process_id.ids.extract_seq`):
```
Chr1	11234	15678	+	Gypsy	Complete	GAG|POL
Chr1	45123	49876	-	Copia	Complete	GAG|POL|ENV
Chr2	8901	12345	+	Unknown	Partial	GAG
...
```
(Tab-delimited: chromosome, start, end, strand, superfamily, completeness, domains)

**GNU split behavior with `-n l/100`**:
- Creates exactly 100 output files: `xaa`, `xab`, ..., `xdl`, `xdm`, etc.
- Distributes lines **equally** across chunks using **round-robin**
- Formula: `chunk_for_line_i = (i * num_chunks) / total_lines`

**Example with 39 lines**:
```
Lines per chunk: floor(39 / 100) = 0 lines (base)
Remainder: 39 % 100 = 39 lines to distribute

Result:
- Chunks 0-38 (xaa-xbm): 1 line each
- Chunks 39-99 (xbn-xdl): 0 lines each (EMPTY)
```

**Verification** (test_clean_env):
```bash
$ ls test_clean_env/LTRFiles/x* | wc -l
100

$ ls -lh test_clean_env/LTRFiles/x* | grep " 0 " | wc -l
61

$ wc -l test_clean_env/Others/test_clean_env.ids.extract_seq
39 lines
```

**Result**: **61 empty files created** (61% waste)

---

### 1.2 Problems with Current Splitting

#### Problem 1: Fixed Chunk Count (Line 337)

**Issue**: Hard-coded 100 chunks regardless of input size

**Impact**:
- Small genome (39 LTRs) → 61 empty files
- Large genome (1000 LTRs) → 10 lines per chunk (acceptable)
- Tiny genome (10 LTRs) → 90 empty files

**Wasted resources**:
```bash
# For 39 LTR elements:
Empty files created: 61
Empty file I/O operations: 61 open() + 61 close()
Empty process spawns: 61 (LTR_Seq_threads.py processes each file)
Disk inodes wasted: 61
```

#### Problem 2: Non-Adaptive Splitting

**Issue**: No intelligence about input characteristics

**Scenarios**:
1. **Few LTR elements** (< 100): Creates mostly empty files
2. **Many LTR elements** (> 1000): Creates unnecessarily many chunks
3. **Variable-sized sequences**: Ignores sequence length (some chunks get all short sequences)

**Comparison to Mechanism A** (cut.pl):
- cut.pl: Splits based on **sequence size** (5 Mb)
- split: Splits based on **line count** (fixed 100)
- cut.pl adapts to genome size ✅
- split does NOT adapt ❌

#### Problem 3: Inefficient Parallelization

**Current flow**:
```python
# LTR_Seq_threads.py (line 48-49)
data = sorted(glob.glob(f"{LTRfiles}/x*"))  # Finds all 100 files
with Pool(nprocess) as p:
    p.map(run_one, data)  # Processes all 100, including 61 empty
```

**Problem**:
- Spawns processes for empty files
- Each process opens empty file, reads 0 lines, exits
- Multiprocessing overhead (fork, join) for no work

**Actual work**:
```
Total chunks: 100
Non-empty: 39
Empty: 61
Wasted process spawns: 61
Wasted CPU cycles: nprocess × 61 × (fork + file_open + check_empty + exit)
```

#### Problem 4: Risk of Empty FASTA Output

**Scenario**: If extractseq script doesn't handle empty input correctly

```python
# Hypothetical bug in extractseq-id-start-end.py
with open(coords_file) as f:
    for line in f:  # Empty file: zero iterations
        extract_sequence(...)
        write_to_output(out_fa)  # Never called

# Result: No output written for this chunk
```

**If output validation expects exactly 100 chunk results**: Pipeline could fail or silently produce incomplete data.

---

### 1.3 Why It Works Despite Problems

**Reason 1**: Tab-delimited input, not FASTA
- Input is coordinate file (TSV), not FASTA sequences
- Line-based split is valid for TSV (each line is independent)
- Empty files don't corrupt data structure

**Reason 2**: LTR_Seq_threads.py handles empty files gracefully
- `glob.glob()` finds all files (including empty)
- `extractseq` script reads empty file → 0 sequences extracted → no crash
- Output file is appended incrementally (empty chunks contribute nothing)

**Reason 3**: Low LTR count in test data
- Test genome (Arabidopsis Chr1, 30 Mb) → 39 LTRs
- 39 non-empty chunks sufficient for correctness
- Waste is "only" 61 files (small absolute overhead)

**BUT**: This is fragile and doesn't scale to production use.

---

## 2. Scalability Analysis

### 2.1 Performance Impact Across Genome Sizes

| Genome | Size | Typical LTR Count | Chunks Created | Empty Files | Efficiency |
|--------|------|-------------------|----------------|-------------|------------|
| Arabidopsis (test) | 30 Mb | 39 | 100 | 61 | 39% |
| Arabidopsis (full) | 119 Mb | ~150 | 100 | 0 | 100% |
| Rice | 374 Mb | ~500 | 100 | 0 | 100% |
| Maize | 2.1 Gb | ~3000 | 100 | 0 | 100% ⚠️ |
| Wheat | 14 Gb | ~10000 | 100 | 0 | 100% ⚠️ |

⚠️ **Large genomes**: 100 chunks insufficient for parallelization
- Maize: 3000 LTRs / 100 chunks = 30 LTRs per chunk
- Wheat: 10000 LTRs / 100 chunks = 100 LTRs per chunk
- Bottleneck: Limited parallelism (max 100 workers)

### 2.2 I/O and Process Overhead

**Measurements** (estimated from test run):

```bash
# Empty file overhead
Empty file creation: 61 × ~10 µs = 610 µs
Empty file reads: 61 × ~50 µs = 3.05 ms
Empty process spawns: 61 × ~5 ms = 305 ms
Total wasted time: ~308 ms per run
```

**Impact**:
- Small genomes: 308 ms overhead (negligible compared to ~12 min total)
- Large genomes: If LTR count < 100 → same waste
- HPC batch jobs: Wasted queue slots for empty chunks

---

## 3. Optimized Splitting Strategy

### 3.1 Design Principles

1. **FASTA-record aware** (for future FASTA splitting, if needed)
2. **Adaptive chunk count** (scale to input size)
3. **No empty chunks** (skip or eliminate)
4. **Minimize disk I/O** (fewer files = less overhead)
5. **Load balancing** (distribute work evenly across workers)
6. **HPC-ready** (suitable for batch job arrays)

### 3.2 Proposed Algorithm

#### For Tab-Delimited Coordinate Files (Current Use Case)

**Goal**: Split `$process_id.ids.extract_seq` intelligently

**Algorithm**:
```python
def smart_split_tsv(input_file, max_chunks=None, target_lines_per_chunk=None):
    """
    Split TSV file into chunks based on actual content.

    Parameters:
    - max_chunks: Maximum number of chunks (default: None = auto)
    - target_lines_per_chunk: Target lines per chunk (default: None = auto)

    Auto mode:
    - If lines < 100: Create min(lines, nthreads * 4) chunks
    - If lines >= 100: Create min(100, lines / 10) chunks
    """

    # Count lines
    with open(input_file) as f:
        total_lines = sum(1 for _ in f)

    if total_lines == 0:
        return []  # No chunks needed

    # Determine optimal chunk count
    if max_chunks is None and target_lines_per_chunk is None:
        # Auto mode
        nthreads = get_thread_count()
        if total_lines < 100:
            num_chunks = min(total_lines, nthreads * 4)
        else:
            num_chunks = min(100, total_lines // 10)
    elif max_chunks:
        num_chunks = min(max_chunks, total_lines)
    else:
        num_chunks = max(1, total_lines // target_lines_per_chunk)

    # Calculate lines per chunk (with remainder distribution)
    base_lines = total_lines // num_chunks
    remainder = total_lines % num_chunks

    # Split file
    chunks = []
    with open(input_file) as f:
        for i in range(num_chunks):
            chunk_size = base_lines + (1 if i < remainder else 0)
            chunk_file = f"{input_file}.chunk{i:04d}"

            with open(chunk_file, 'w') as out:
                for _ in range(chunk_size):
                    line = f.readline()
                    if line:
                        out.write(line)

            chunks.append(chunk_file)

    return chunks
```

**Example results**:

| Total Lines | nthreads | Chunks Created | Lines per Chunk | Empty Files |
|-------------|----------|----------------|-----------------|-------------|
| 39 | 4 | 16 | 2-3 | 0 |
| 100 | 4 | 16 | 6-7 | 0 |
| 500 | 4 | 50 | 10 | 0 |
| 3000 | 4 | 100 | 30 | 0 |

**Benefits**:
- **39 LTRs**: 61% fewer files (39 → 16 chunks)
- **No empty files**: Every chunk has work
- **Better parallelism**: 16 chunks × 4 threads = good utilization
- **Scalable**: Adapts to small and large inputs

---

#### For FASTA Files (Future-Proofing)

**Goal**: Split genome FASTA for parallel LTR detection

**Two strategies**:

##### Strategy A: Contig-Based Splitting (Recommended)

```python
def split_fasta_by_contig(fasta_file, max_chunks=None, target_bases_per_chunk=50_000_000):
    """
    Split FASTA by grouping contigs to reach target bases per chunk.
    Never splits within a contig.
    """

    # First pass: collect contig sizes
    contigs = []
    with open(fasta_file) as f:
        for record in SeqIO.parse(f, "fasta"):
            contigs.append((record.id, len(record.seq)))

    total_bases = sum(size for _, size in contigs)

    # Determine chunk count
    if max_chunks is None:
        num_chunks = max(1, total_bases // target_bases_per_chunk)
    else:
        num_chunks = min(max_chunks, len(contigs))

    # Bin-packing: assign contigs to chunks
    # Use greedy algorithm (sorted by size, largest first)
    contigs.sort(key=lambda x: x[1], reverse=True)

    chunks = [[] for _ in range(num_chunks)]
    chunk_sizes = [0] * num_chunks

    for contig_id, contig_size in contigs:
        # Assign to chunk with smallest current size
        min_idx = chunk_sizes.index(min(chunk_sizes))
        chunks[min_idx].append(contig_id)
        chunk_sizes[min_idx] += contig_size

    # Write chunks
    chunk_files = []
    for i, contig_list in enumerate(chunks):
        if not contig_list:
            continue  # Skip empty chunks

        chunk_file = f"{fasta_file}.chunk{i:04d}.fa"
        with open(chunk_file, 'w') as out:
            for record in SeqIO.parse(fasta_file, "fasta"):
                if record.id in contig_list:
                    SeqIO.write(record, out, "fasta")

        chunk_files.append(chunk_file)

    return chunk_files
```

**Advantages**:
- ✅ Biologically meaningful (preserves contigs)
- ✅ No coordinate adjustment needed
- ✅ Balanced chunk sizes (bin-packing)
- ✅ Works for fragmented assemblies
- ❌ May create unbalanced chunks if few large contigs

##### Strategy B: Fixed-Size Splitting (Current cut.pl Approach)

Keep existing `cut.pl` but with improvements:

```python
def split_fasta_fixed_size(fasta_file, chunk_size=5_000_000):
    """
    Split FASTA into fixed-size chunks (may split contigs).
    Coordinate adjustment required downstream.
    """
    # (Similar to cut.pl but with better handling)
    # See cut.pl lines 29-45
```

**When to use**:
- Very large contigs (single chromosome > target chunk size)
- Need maximum parallelism
- Downstream tools can handle coordinate adjustment (LTR_HARVEST_parallel already does this)

---

### 3.3 Implementation: smart_split_tsv.py

```python
#!/usr/bin/env python3
"""
Intelligent splitting for tab-delimited coordinate files.
Eliminates empty chunks and adapts to input size.

Usage:
    python3 smart_split_tsv.py <input_file> <output_dir> [options]

Options:
    --threads N       Number of threads (default: 4)
    --max-chunks N    Maximum chunks (default: auto)
    --chunk-size N    Target lines per chunk (default: auto)
    --prefix NAME     Output file prefix (default: chunk)

Example:
    python3 smart_split_tsv.py coords.tsv ./chunks --threads 4
    # Creates: chunk0000, chunk0001, ..., chunk000N (no empty files)
"""

import sys
import os
import argparse
from pathlib import Path

def count_lines(file_path):
    """Count non-empty lines in file."""
    with open(file_path) as f:
        return sum(1 for line in f if line.strip())

def determine_chunk_count(total_lines, nthreads, max_chunks=None):
    """
    Determine optimal number of chunks based on input size.

    Strategy:
    - Small inputs (< 100 lines): min(lines, nthreads * 4)
    - Large inputs (>= 100 lines): min(max_chunks, lines // 10)

    Rationale:
    - nthreads * 4: Allows ~4 batches per worker (good task granularity)
    - lines // 10: ~10 lines per chunk (reasonable parallelism)
    - Never exceed total_lines (no empty chunks)
    """
    if total_lines == 0:
        return 0

    if total_lines < 100:
        optimal = min(total_lines, nthreads * 4)
    else:
        optimal = min(max_chunks or 100, max(10, total_lines // 10))

    return max(1, min(optimal, total_lines))

def split_file(input_file, output_dir, num_chunks, prefix="chunk"):
    """
    Split file into num_chunks parts with balanced line distribution.

    Returns:
        List of created chunk file paths (no empty files).
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Read all lines
    with open(input_file) as f:
        lines = [line for line in f if line.strip()]

    total_lines = len(lines)
    if total_lines == 0:
        print(f"Warning: Input file is empty: {input_file}", file=sys.stderr)
        return []

    # Calculate distribution
    base_lines = total_lines // num_chunks
    remainder = total_lines % num_chunks

    # Split and write
    chunk_files = []
    line_idx = 0

    for i in range(num_chunks):
        chunk_size = base_lines + (1 if i < remainder else 0)
        if chunk_size == 0:
            break  # No more lines to distribute

        chunk_path = output_dir / f"{prefix}{i:04d}"
        with open(chunk_path, 'w') as out:
            for _ in range(chunk_size):
                out.write(lines[line_idx])
                line_idx += 1

        chunk_files.append(str(chunk_path))

    return chunk_files

def main():
    parser = argparse.ArgumentParser(
        description="Smart TSV splitting with no empty chunks",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    parser.add_argument("input_file", help="Input TSV file")
    parser.add_argument("output_dir", help="Output directory for chunks")
    parser.add_argument("--threads", "-t", type=int, default=4,
                        help="Number of threads (default: 4)")
    parser.add_argument("--max-chunks", type=int, default=None,
                        help="Maximum number of chunks (default: auto)")
    parser.add_argument("--chunk-size", type=int, default=None,
                        help="Target lines per chunk (default: auto)")
    parser.add_argument("--prefix", default="chunk",
                        help="Output file prefix (default: chunk)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Verbose output")

    args = parser.parse_args()

    # Validate input
    if not os.path.exists(args.input_file):
        print(f"Error: Input file not found: {args.input_file}", file=sys.stderr)
        sys.exit(1)

    # Count lines
    total_lines = count_lines(args.input_file)

    if args.verbose:
        print(f"Input file: {args.input_file}")
        print(f"Total lines: {total_lines}")

    if total_lines == 0:
        print("Warning: Input file is empty, no chunks created.")
        sys.exit(0)

    # Determine chunk count
    if args.chunk_size:
        num_chunks = max(1, total_lines // args.chunk_size)
    else:
        num_chunks = determine_chunk_count(total_lines, args.threads, args.max_chunks)

    if args.verbose:
        print(f"Creating {num_chunks} chunks...")
        print(f"Lines per chunk: {total_lines // num_chunks} ± {total_lines % num_chunks}")

    # Split file
    chunk_files = split_file(args.input_file, args.output_dir, num_chunks, args.prefix)

    # Report
    if args.verbose:
        print(f"\nCreated {len(chunk_files)} chunks:")
        for cf in chunk_files:
            lines = count_lines(cf)
            print(f"  {os.path.basename(cf)}: {lines} lines")
    else:
        print(f"Created {len(chunk_files)} chunks in {args.output_dir}")

    # Verify no empty files
    empty_count = sum(1 for cf in chunk_files if count_lines(cf) == 0)
    if empty_count > 0:
        print(f"Warning: {empty_count} empty chunks created!", file=sys.stderr)
        sys.exit(1)

    print(f"✓ All chunks non-empty (total: {len(chunk_files)})")

if __name__ == "__main__":
    main()
```

---

## 4. Integration Plan

### 4.1 Modifications to MegaLTR.sh

**Current code** (line 333-338):
```bash
awk -F "\t" '{ print  $2"\t"$3"\t"$4"\t"$5"\t"$32"\t"$33"\t"$34 }' $Others/LTR_Table_TEsorter_Digest.tsv > $Others/$process_id.ids.extract_seq
mkdir -p $userpath/LTRFiles
LTRFiles=$userpath/LTRFiles
cd $LTRFiles
split -n l/100 $Others/$process_id.ids.extract_seq
python3 $RUN/LTR_Seq_threads.py $userpath/$process_id.fna  $LTRFiles $Collected_Files $threads $RUN/extractseq-id-start-end.py
```

**Optimized code**:
```bash
awk -F "\t" '{ print  $2"\t"$3"\t"$4"\t"$5"\t"$32"\t"$33"\t"$34 }' $Others/LTR_Table_TEsorter_Digest.tsv > $Others/$process_id.ids.extract_seq
mkdir -p $userpath/LTRFiles
LTRFiles=$userpath/LTRFiles

# --- Smart splitting: adaptive chunk count, no empty files ---
python3 $RUN/smart_split_tsv.py \
    $Others/$process_id.ids.extract_seq \
    $LTRFiles \
    --threads $threads \
    --prefix chunk \
    --verbose

# --- Update LTR_Seq_threads.py to use new chunk naming ---
python3 $RUN/LTR_Seq_threads.py $userpath/$process_id.fna  $LTRFiles $Collected_Files $threads $RUN/extractseq-id-start-end.py
```

**Changes required**:
1. Replace `split -n l/100` with `smart_split_tsv.py`
2. Update `LTR_Seq_threads.py` glob pattern (line 27):
   ```python
   # OLD: data = sorted(glob.glob(f"{LTRfiles}/x*"))
   # NEW: data = sorted(glob.glob(f"{LTRfiles}/chunk*"))
   ```

---

### 4.2 Modified LTR_Seq_threads.py

**Current** (line 27):
```python
data = sorted(glob.glob(f"{LTRfiles}/x*"))
```

**Updated**:
```python
# Support both old (x*) and new (chunk*) naming
data = sorted(glob.glob(f"{LTRfiles}/chunk*"))
if not data:
    # Fallback to old naming for backward compatibility
    data = sorted(glob.glob(f"{LTRfiles}/x*"))

if not data:
    raise FileNotFoundError(f"No chunk files found in {LTRfiles}")
```

**Benefits**:
- Backward compatible with old split files
- Supports new smart splitting
- Clear error message if no chunks found

---

## 5. Validation Strategy

### 5.1 Testing Approach

Follow supervisor's recommendation: **test after each change**

#### Test 1: Verify smart_split_tsv.py Correctness

```bash
# Create test input
seq 1 39 > test_input.txt  # 39 lines

# Run smart splitter
python3 smart_split_tsv.py test_input.txt ./test_chunks --threads 4 --verbose

# Verify output
echo "Expected: ~16 chunks (39 lines, 4 threads)"
ls test_chunks/chunk* | wc -l

# Check for empty files
ls -lh test_chunks/ | grep " 0 "
# Expected: (no output - no empty files)

# Verify all lines preserved
cat test_chunks/chunk* | wc -l
# Expected: 39

# Verify line distribution
for f in test_chunks/chunk*; do echo "$f: $(wc -l < $f) lines"; done
# Expected: 2-3 lines per chunk
```

#### Test 2: Integration with LTR_Seq_threads.py

```bash
# Use real MegaLTR output
INPUT="test_clean_env/Others/test_clean_env.ids.extract_seq"
OUTPUT_DIR="./test_smart_split"

# Run smart splitter
python3 bin/RUN/smart_split_tsv.py $INPUT $OUTPUT_DIR --threads 4 --verbose

# Run LTR_Seq_threads.py with new chunks
python3 bin/RUN/LTR_Seq_threads.py \
    test_clean_env/test_clean_env.fna \
    $OUTPUT_DIR \
    ./test_output \
    4 \
    bin/RUN/extractseq-id-start-end.py

# Compare output to original
diff test_clean_env/Collected_Files/LTR-RT_Sequence.fa \
     test_output/LTR-RT_Sequence.fa
# Expected: Files identical (or permutation of same sequences)
```

#### Test 3: Full Pipeline Test

```bash
# Run complete pipeline with optimized splitting
bash MegaLTR.sh \
    -A 3 \
    -F Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
    -G Data_for_test/Arabidopsis_thaliana.gff \
    -P test_optimized_split \
    -t 4 \
    -R 0.000000015

# Verify no empty chunk files
ls test_optimized_split/LTRFiles/ | wc -l
# Expected: ~16 (not 100)

empty_count=$(ls -lh test_optimized_split/LTRFiles/ | grep " 0 " | wc -l)
echo "Empty files: $empty_count"
# Expected: 0

# Compare scientific output
diff test_clean_env/Collected_Files/LTR_Table_TEsorter_Digest.tsv \
     test_optimized_split/Collected_Files/LTR_Table_TEsorter_Digest.tsv
# Expected: Files identical
```

#### Test 4: Performance Benchmarking

```bash
# Measure splitting time
time split -n l/100 test_input.txt
# vs
time python3 smart_split_tsv.py test_input.txt ./chunks --threads 4

# Measure total pipeline time (old vs new)
# Expected: Negligible difference for small genomes, improvement for large genomes
```

#### Test 5: Edge Cases

```bash
# Empty input
echo -n "" > empty.txt
python3 smart_split_tsv.py empty.txt ./chunks --threads 4
# Expected: "Warning: Input file is empty, no chunks created."

# Single line input
echo "Chr1 100 200 +" > single.txt
python3 smart_split_tsv.py single.txt ./chunks --threads 4
# Expected: 1 chunk created

# Very large input (simulate 10,000 LTRs)
seq 1 10000 > large.txt
python3 smart_split_tsv.py large.txt ./chunks --threads 4 --verbose
# Expected: 100 chunks, 100 lines per chunk, no empty files
```

---

## 6. Expected Improvements

### 6.1 Quantitative Metrics

| Metric | Before (split -n l/100) | After (smart_split_tsv.py) | Improvement |
|--------|-------------------------|----------------------------|-------------|
| **Arabidopsis Chr1 (39 LTRs)** |
| Chunks created | 100 | 16 | 84% fewer files |
| Empty files | 61 | 0 | 100% elimination |
| Disk I/O operations | 200 | 32 | 84% reduction |
| Process spawns | 100 | 16 | 84% reduction |
| Lines per chunk | 0-1 | 2-3 | Better balance |
| **Rice (500 LTRs)** |
| Chunks created | 100 | 50 | 50% fewer files |
| Empty files | 0 | 0 | No change |
| Lines per chunk | 5 | 10 | Better granularity |
| **Maize (3000 LTRs)** |
| Chunks created | 100 | 100 | Same |
| Empty files | 0 | 0 | Same |
| Lines per chunk | 30 | 30 | Same |
| Parallelization | Limited (30/chunk) | Optimal (30/chunk) | Same |

### 6.2 Qualitative Benefits

1. **Robustness**: No empty file handling needed downstream
2. **Scalability**: Adapts to small and large genomes automatically
3. **Maintainability**: Clear logic, documented algorithm
4. **HPC-ready**: Efficient resource usage (no wasted job slots)
5. **Debuggability**: Verbose mode shows chunk distribution
6. **Future-proof**: Easy to extend to FASTA splitting if needed

---

## 7. Recommendations

### 7.1 Immediate Actions (Phase 5)

1. **Implement smart_split_tsv.py** (see Section 3.3)
2. **Test standalone** (Section 5.1, Tests 1-2)
3. **Update MegaLTR.sh** (Section 4.1)
4. **Update LTR_Seq_threads.py** (Section 4.2)
5. **Run full pipeline test** (Section 5.1, Test 3)
6. **Verify scientific output identical** (diff comparison)
7. **Measure performance** (Section 5.1, Test 4)
8. **Document in Progress Report #5**

### 7.2 Future Enhancements (Phase 6+)

1. **Genome FASTA splitting**: Implement `split_fasta_by_contig()` for parallelizing LTR_HARVEST
2. **Nextflow integration**: Use splitting as part of scatter-gather pattern
3. **Dynamic chunking**: Adjust chunk count based on available CPU/memory
4. **Load balancing**: Sort LTRs by length, distribute to balance work
5. **Compressed output**: Write chunks as .gz to save disk space

### 7.3 Not Recommended

❌ **Replacing cut.pl** (LTR_HARVEST_parallel)
- Current implementation works well for genome splitting
- Coordinate adjustment logic is complex and tested
- Risk vs. benefit ratio unfavorable

✅ **Focus**: Optimize coordinate file splitting (MegaLTR.sh line 337) where problem is clear and impact is measurable.

---

## 8. Conclusion

The current FASTA splitting implementation has a **critical efficiency bug**:
- Creates **61% empty files** for small genomes
- Wastes disk I/O, process spawns, and HPC resources
- Uses fixed chunk count (100) regardless of input size

**Proposed solution**:
- Adaptive splitting algorithm based on input size and thread count
- Zero empty files guaranteed
- 84% reduction in file operations for small genomes
- Maintains correctness and scientific output
- Minimal code changes, high impact

**Ready for implementation**: All design, code, and validation strategies documented.

---

**Next**: Create `smart_split_tsv.py` and integrate into MegaLTR.sh (Progress Report #5).
