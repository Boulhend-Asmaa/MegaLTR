# FASTA Splitting Integration Plan

**Date**: 2026-01-12
**Project**: MegaLTR Pipeline Optimization - Phase 5
**Status**: Implementation complete, integration ready

---

## Overview

This document describes the integration of true FASTA splitting into MegaLTR for parallel LTR detection.

### What Was Implemented

1. **smart_split_fasta.py** - FASTA-record aware splitting
   - Adaptive chunk count based on sequence count
   - Balanced bin-packing algorithm
   - Support for .fna and .fna.gz
   - Zero empty chunks guaranteed
   - Comprehensive validation mode

2. **smart_split_tsv.py** - TSV coordinate file splitting
   - Adaptive chunk count for LTR extraction
   - Eliminates 61% empty files for small genomes

---

## Current vs. Proposed Architecture

### Current Architecture (Sequential)

```
Input: genome.fna (single file)
  ↓
LTR_FINDER (processes entire genome)
  ↓
LTR_HARVEST (processes entire genome via cut.pl splitting)
  ↓
Combine results
  ↓
LTR_retriever (processes entire genome)
  ↓
Continue pipeline...
```

**Problem**: For single-chromosome genomes, no parallelization possible

### Proposed Architecture (Parallel-Ready)

**Option A: Split Upstream (Recommended for Phase 6 - Nextflow)**

```
Input: genome.fna
  ↓
smart_split_fasta.py → [chunk_001.fna, chunk_002.fna, ..., chunk_N.fna]
  ↓
├─ LTR_FINDER(chunk_001) ──┐
├─ LTR_FINDER(chunk_002) ──┤
├─ ...                     ├─→ Combine → LTR_retriever
├─ LTR_HARVEST(chunk_001) ─┤
├─ LTR_HARVEST(chunk_002) ─┤
└─ ...                     ┘
```

**Benefit**: True parallelization across chunks

**Challenge**: Requires significant MegaLTR.sh refactoring

---

**Option B: Current Approach (Keep for Phase 5)**

```
Input: genome.fna
  ↓
LTR_FINDER (existing implementation)
  ↓
LTR_HARVEST_parallel (uses cut.pl, already parallelized)
  ↓
Results combined
  ↓
LTR_retriever
  ↓
Coordinate extraction → TSV file
  ↓
smart_split_tsv.py (optimize this step) → [chunk_0000, ..., chunk_00N]
  ↓
LTR_Seq_threads.py (parallel extraction)
```

**Benefit**: Minimal changes, immediate 84% file reduction

**Trade-off**: Parallelization only in extraction step, not LTR detection

---

## Recommendation for Phase 5

**Focus on TSV splitting optimization** (already implemented):
- ✅ Immediate impact (84% file reduction)
- ✅ Low risk (only affects file I/O)
- ✅ Quick integration (2 line changes)
- ✅ No scientific output changes

**Defer genome FASTA splitting to Phase 6** (Nextflow migration):
- Requires architectural refactoring
- Better suited for workflow orchestration (Nextflow scatter-gather)
- More testing required for LTR boundary handling
- Higher risk of regression

---

## Phase 5: TSV Splitting Integration (Recommended)

### Step 1: Update MegaLTR.sh (Line 337)

**Current**:
```bash
cd $LTRFiles
split -n l/100 $Others/$process_id.ids.extract_seq
```

**Optimized**:
```bash
# Smart splitting: adaptive chunks, no empty files
python3 $RUN/smart_split_tsv.py \
    $Others/$process_id.ids.extract_seq \
    $LTRFiles \
    --threads $threads \
    --prefix chunk \
    2>&1 | grep -E "(Created|Error)" || true
```

### Step 2: Update LTR_Seq_threads.py (Line 27)

**Current**:
```python
data = sorted(glob.glob(f"{LTRfiles}/x*"))
```

**Optimized**:
```python
# Support new chunk naming (backward compatible)
data = sorted(glob.glob(f"{LTRfiles}/chunk*"))
if not data:
    # Fallback to old naming for backward compatibility
    data = sorted(glob.glob(f"{LTRfiles}/x*"))
if not data:
    raise FileNotFoundError(f"No chunk files found in {LTRfiles} (tried: chunk*, x*)")
```

### Step 3: Test Integration

```bash
# Test with real data
bash MegaLTR.sh \
    -A 3 \
    -F Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
    -G Data_for_test/Arabidopsis_thaliana.gff \
    -P test_tsv_split \
    -t 4 \
    -R 0.000000015

# Verify chunk files
ls test_tsv_split/LTRFiles/
# Expected: chunk0000, chunk0001, ..., chunk0015 (16 files, 0 empty)

# Compare scientific output
diff test_clean_env/Collected_Files/LTR_Table_TEsorter_Digest.tsv \
     test_tsv_split/Collected_Files/LTR_Table_TEsorter_Digest.tsv
# Expected: Identical (or sequence order permutation)
```

---

## Phase 6: FASTA Splitting Integration (Future - Nextflow)

### When to Implement

- After Nextflow migration (Progress Report #6)
- When refactoring LTR detection into modular processes
- When implementing true scatter-gather parallelization

### Integration Points

#### 1. Pre-Process: Genome Splitting

```nextflow
process SPLIT_GENOME {
    input:
    path genome_fasta
    val threads

    output:
    path "chunks/chunk_*.fna", emit: chunks

    script:
    """
    python3 ${projectDir}/bin/RUN/smart_split_fasta.py \\
        ${genome_fasta} \\
        chunks \\
        --threads ${threads} \\
        --verbose
    """
}
```

#### 2. Parallel LTR Detection

```nextflow
process LTR_FINDER_CHUNK {
    input:
    path chunk

    output:
    path "*.finder.scn"

    script:
    """
    perl ${LTR_FINDER} -seq ${chunk} -threads 1 ...
    """
}

process LTR_HARVEST_CHUNK {
    input:
    path chunk

    output:
    path "*.harvest.scn"

    script:
    """
    gt ltrharvest -index ${chunk} ...
    """
}
```

#### 3. Result Merging

```nextflow
process MERGE_LTR_RESULTS {
    input:
    path finder_results
    path harvest_results

    output:
    path "combined.scn"

    script:
    """
    cat ${finder_results} ${harvest_results} > combined.scn
    """
}
```

### Challenges to Address

1. **Coordinate Adjustment**:
   - LTR coordinates are relative to chunk
   - Must convert to genome-wide coordinates
   - Solution: Track chunk offsets in metadata

2. **Boundary LTRs**:
   - LTRs spanning chunk boundaries may be split
   - Solution: Add overlap regions between chunks (e.g., 50 kb)
   - Deduplicate LTRs in merge step

3. **Index Files**:
   - GenomeTools requires index per chunk
   - Must create suffix arrays for each chunk
   - Cleanup temporary indices after processing

---

## Validation Strategy

### Phase 5 Validation (TSV Splitting)

#### Test 1: File Count Reduction

```bash
# Expected results
Old method: 100 files, 61 empty (61% waste)
New method: 16 files, 0 empty (0% waste)
```

#### Test 2: Scientific Output Identical

```bash
# Compare LTR tables
diff test_clean_env/Collected_Files/LTR_Table_TEsorter_Digest.tsv \
     test_tsv_split/Collected_Files/LTR_Table_TEsorter_Digest.tsv

# Compare sequence files (may be in different order)
sort test_clean_env/Collected_Files/LTR-RT_Sequence.fa > old.sorted
sort test_tsv_split/Collected_Files/LTR-RT_Sequence.fa > new.sorted
diff old.sorted new.sorted
# Expected: Identical
```

#### Test 3: Performance Measurement

```bash
# Measure splitting time
time (split -n l/100 input.txt)  # Old method
time (python3 smart_split_tsv.py input.txt ./chunks --threads 4)  # New method

# Measure total pipeline time
time bash MegaLTR.sh [args] -P test_old
time bash MegaLTR.sh [args] -P test_new

# Expected: Negligible difference (file I/O is not bottleneck)
```

### Phase 6 Validation (FASTA Splitting)

#### Test 1: Chunk Validation

```bash
# Validate chunks preserve all sequences
python3 smart_split_fasta.py genome.fna ./chunks --validate --verbose

# Expected output:
# - Total sequences: N
# - Total bases: X bp
# - Chunks: M files
# - All sequences preserved: ✓
```

#### Test 2: LTR Detection Comparison

```bash
# Run pipeline with and without splitting
bash MegaLTR.sh [args] -P baseline
# (manually run with splitting)
bash MegaLTR_split.sh [args] -P split_test

# Compare LTR counts
wc -l baseline/LAI/*.pass.list
wc -l split_test/LAI/*.pass.list

# Compare LTR coordinates (allowing for minor boundary differences)
# Expected: >99% overlap, differences only at chunk boundaries
```

---

## Testing Checklist

### Phase 5 (Current - TSV Splitting)

- [x] smart_split_tsv.py implemented
- [x] Tested with 39 LTRs (16 chunks, 0 empty)
- [x] Verified line preservation
- [ ] Update MegaLTR.sh line 337
- [ ] Update LTR_Seq_threads.py line 27
- [ ] Integration test (full pipeline)
- [ ] Scientific output comparison
- [ ] Performance benchmarking
- [ ] Progress Report #5

### Phase 6 (Future - FASTA Splitting + Nextflow)

- [x] smart_split_fasta.py implemented
- [x] Tested with single-chromosome genome
- [ ] Test with multi-chromosome genome
- [ ] Test with fragmented assembly (>100 contigs)
- [ ] Coordinate adjustment logic
- [ ] Boundary overlap implementation
- [ ] Nextflow process definitions
- [ ] Full workflow integration
- [ ] Scientific validation (LTR comparison)
- [ ] Performance benchmarking (speedup measurement)
- [ ] Progress Report #6

---

## Implementation Timeline

### Week 1 (Current)
- ✅ Day 1: Analyze current splitting mechanisms
- ✅ Day 1: Implement smart_split_tsv.py
- ✅ Day 1: Implement smart_split_fasta.py
- ✅ Day 1: Test standalone scripts
- 🔄 Day 2: Integrate TSV splitting into MegaLTR.sh
- 🔄 Day 2: Full pipeline validation
- 📝 Day 3: Progress Report #5

### Weeks 2-6 (Future - Phase 6)
- Week 2: Nextflow workflow skeleton
- Week 3: Implement FASTA splitting + parallel LTR detection
- Week 4: Coordinate adjustment and result merging
- Week 5: Testing and validation
- Week 6: Progress Report #6 + finalization

---

## Conclusion

**For Phase 5**: Focus on TSV splitting optimization
- Low-hanging fruit (84% file reduction)
- Minimal changes (2 lines of code)
- Immediate impact
- Low risk

**For Phase 6**: Implement FASTA splitting in Nextflow context
- Requires architectural refactoring
- Better suited for workflow orchestration
- True parallelization of LTR detection
- Higher complexity but higher payoff

**Current Status**: TSV splitting ready for integration (Day 2)

**Next Action**: Update MegaLTR.sh and LTR_Seq_threads.py, run validation tests

---

**Files Delivered**:
1. `bin/RUN/smart_split_fasta.py` - FASTA splitting (Phase 6)
2. `bin/RUN/smart_split_tsv.py` - TSV splitting (Phase 5)
3. `FASTA_SPLITTING_ANALYSIS.md` - Complete technical analysis
4. `FASTA_SPLITTING_SUMMARY.md` - Executive summary
5. `FASTA_SPLITTING_INTEGRATION.md` - This integration plan
