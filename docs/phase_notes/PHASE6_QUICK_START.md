# Phase 6: Nextflow Migration - Quick Start Guide

**Branch**: `feat/nextflow-migration`
**Timeline**: Tight deadline - aggressive approach
**Strategy**: Working minimal version → iterate and expand

---

## Fast-Track Implementation Plan

### Week 1: Minimal Working Workflow (Priority 1)
**Goal**: Get basic Nextflow pipeline running end-to-end

**Tasks**:
- [x] Install Nextflow
- [ ] Create `main.nf` with basic structure
- [ ] Convert 3 critical processes:
  1. `prepare_genome` - Prepare input files
  2. `ltr_detection` - Run LTR detection (non-parallel first)
  3. `collect_results` - Gather outputs
- [ ] Test with Arabidopsis chr1
- [ ] Verify scientific equivalence (compare vs Bash)

**Deliverable**: Working Nextflow pipeline (simplified, no parallelization)

---

### Week 2: Add Parallelization (Priority 2)
**Goal**: Implement scatter-gather for performance

**Tasks**:
- [ ] Integrate `smart_split_fasta.py` for genome splitting
- [ ] Parallelize LTR detection (scatter-gather)
- [ ] Integrate `smart_split_tsv.py` for sequence extraction
- [ ] Test parallelization efficiency

**Deliverable**: Parallelized Nextflow pipeline

---

### Week 3: Production Features (Priority 3)
**Goal**: Make it production-ready

**Tasks**:
- [ ] Add `-resume` capability
- [ ] Error handling and retry logic
- [ ] Resource management (CPU/memory)
- [ ] Container support (Docker/Singularity)
- [ ] HPC cluster testing (SLURM)

**Deliverable**: Production-ready pipeline

---

### Week 4: Final Testing & Documentation (Priority 4)
**Goal**: Complete and document

**Tasks**:
- [ ] Test on multiple genomes
- [ ] Performance benchmarking
- [ ] Write Progress Report #6
- [ ] User documentation
- [ ] Project presentation

**Deliverable**: Complete MegaLTR Nextflow pipeline

---

## Critical Path (Do These First)

### Today (Day 1):
1. ✅ Install Nextflow
2. ⏳ Create `main.nf` skeleton
3. ⏳ Define first 3 processes
4. ⏳ Test "hello world" Nextflow execution

### Tomorrow (Day 2):
1. Convert genome preparation to Nextflow
2. Convert LTR_FINDER to Nextflow process
3. Test with small dataset

### Day 3-5:
1. Add LTR_HARVEST process
2. Add result merging
3. Complete minimal workflow
4. Scientific equivalence validation

---

## Learn-By-Doing Approach

**Instead of extensive tutorials**: Learn Nextflow concepts as needed

**Resources** (quick reference only):
- Nextflow docs: https://www.nextflow.io/docs/latest/
- Quick start: https://www.nextflow.io/docs/latest/getstarted.html
- Process: https://www.nextflow.io/docs/latest/process.html
- Channel: https://www.nextflow.io/docs/latest/channel.html

**Strategy**: Copy patterns from working examples, adapt to MegaLTR

---

## Minimal Viable Workflow (MVW)

Start with this simplified structure:

```
Input: genome.fna, annotation.gff
  ↓
Process: prepare_genome (replaceIDs, etc.)
  ↓
Process: ltr_finder (single run, no splitting yet)
  ↓
Process: ltr_harvest (single run, no splitting yet)
  ↓
Process: merge_results
  ↓
Process: ltr_retriever (simplified - 1 run only)
  ↓
Process: extract_sequences
  ↓
Output: LTR-RT_Sequence.fa, LTR tables
```

**Parallelization comes later** - first goal is working pipeline!

---

## Key Simplifications (Week 1)

To move fast, initially skip:
- ❌ Genome splitting (use whole genome first)
- ❌ 8 parallel LTR_retriever runs (do 1 run)
- ❌ Coordinate splitting (process all at once)
- ❌ Error handling
- ❌ Resource optimization
- ❌ Container support

**Add these in Week 2-3** after basic workflow works!

---

## Success Criteria (Week 1)

✅ Nextflow pipeline runs without errors
✅ Produces LTR-RT_Sequence.fa
✅ Output matches Bash version (same number of LTRs)
✅ Can be run with: `nextflow run main.nf --genome genome.fna --gff annotation.gff`

That's it! Complexity comes later.

---

## Next File to Create

`main.nf` - the main Nextflow workflow file

See `NEXTFLOW_TEMPLATE.nf` for starter template.
