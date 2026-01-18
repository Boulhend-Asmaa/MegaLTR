# MegaLTR Environment Analysis

## Current State

**Original MegaLTR.yml**: 23 top-level dependencies
**Full exported environment**: 184 packages (including transitive dependencies)

---

## Tool Usage Analysis (from MegaLTR.sh)

### Critical Bioinformatics Tools
1. **LTR_retriever** (8 invocations) - Core LTR identification
2. **GenomeTools (gt)** (3 invocations) - LTRdigest, LTRharvest
3. **TEsorter** (1 invocation) - TE classification
4. **vsearch** (5 invocations) - Clustering
5. **clustalw** (1 invocation) - Multiple sequence alignment
6. **RepeatMasker** - Transitive dependency of LTR_retriever
7. **cd-hit** - Transitive dependency
8. **hmmer** - Transitive dependency (TEsorter uses it)

### Language Runtimes
1. **Python 3.10** - All migrated scripts (estimate_K, get-TE-*, join_tables, etc.)
2. **Perl 5** - LTR_FINDER, LTR_HARVEST (embedded in GenomeTools/LTR_retriever)
3. **R 4.x** - Visualization scripts (4 Rscript calls)

### Python Package Requirements
- **numpy** - Used in estimate_K.py
- **pyfaidx** - FASTA indexing (used by LTR_retriever)
- **biopython** - Sequence handling (transitive from LTR_retriever/TEsorter)
- Standard library: sys, os, re, math, multiprocessing, glob, gzip, shutil, random, typing

### R Package Requirements (from Rscript calls in MegaLTR.sh)
- **ggplot2** - Plotting
- **viridis** - Color palettes
- **hrbrthemes** - Plot themes
- **RIdeogram** - Ideogram visualization
- Dependencies: dplyr, tidyr, scales, gridExtra, etc.

---

## What Can Be REMOVED

### 1. Perl (partially)
**Status**: CANNOT REMOVE COMPLETELY
- LTR_FINDER and LTR_HARVEST are Perl scripts (part of LTR_retriever package)
- However, we no longer need perl-bioperl, perl-text-soundex explicitly listed
- These are pulled in automatically by ltr_retriever

**Action**: Remove explicit Perl packages, keep perl runtime (pulled by ltr_retriever)

### 2. Duplicate/Unused Packages

**pthread-stubs**: Unused, low-level library
- Not directly invoked by pipeline
- Action: REMOVE

**gzip**: System tool, not needed in conda
- Already in system PATH
- Action: REMOVE (use system gzip)

**perl-text-soundex**: Specific Perl module
- Not used by our Python scripts
- Action: REMOVE (pulled by ltr_retriever if needed)

**perl-bioperl**: Legacy
- Was needed for old Perl scripts (now migrated)
- Action: REMOVE (pulled by ltr_retriever if needed)

---

## What Must Be KEPT

### Core Tools (pinned versions)
1. **python=3.10.6** - All Python scripts tested with this
2. **genometools-genometools=1.6.6** - gt ltrharvest, gt ltrdigest
3. **ltr_retriever=3.0.4** - Core pipeline
4. **tesorter=1.5.1** - TE classification
5. **clustalw=2.1** - MSA for insertion time
6. **vsearch** - Clustering (version via ltr_retriever)
7. **cd-hit** - Transitive, needed by ltr_retriever
8. **hmmer** - Transitive, needed by tesorter

### Python Packages
1. **numpy** - Used in estimate_K.py
2. **pyfaidx** - FASTA indexing

### R Packages
1. **r-base=4.5.1** - R runtime
2. **r-ggplot2** - Plots
3. **r-viridis** - Colors
4. **r-hrbrthemes** - Themes
5. **r-rideogram** - Ideograms
6. **cairo** - Graphics backend for R

---

## Uncertain Dependencies

### repeatmasker=4.0.6
**Status**: Listed in exported env, but not in MegaLTR.yml
**Usage**: Transitive dependency of LTR_retriever
**Action**: KEEP (implicitly via ltr_retriever), do not pin explicitly

### rmblast
**Status**: RepeatMasker uses rmblast (NCBI BLAST+ variant)
**Action**: KEEP (pulled by repeatmasker)

### entrez-direct
**Status**: NCBI E-utilities
**Usage**: LTR_retriever may download databases
**Action**: KEEP if internet available, otherwise document as optional

---

## Version Pinning Strategy

### Pin EXACTLY (critical for reproducibility)
- python=3.10.6 ✓
- genometools-genometools=1.6.6 ✓
- ltr_retriever=3.0.4 ✓
- tesorter=1.5.1 ✓
- r-base=4.5.1 ✓
- numpy (current: 2.2.6) ✓

### Pin MAJOR.MINOR (allow patch updates)
- clustalw=2.1 ✓
- hmmer=3.4 ✓
- cd-hit=4.8 ✓

### Flexible (let conda resolve)
- R package ecosystem (too many interdependencies)
- Build tools (gcc, make, etc.)

---

## Proposed Clean Environment

### Channels (ORDER MATTERS)
```yaml
channels:
  - conda-forge  # Preferred for most packages
  - bioconda     # Bioinformatics tools
  - defaults     # Fallback
```

**Remove**: `anaconda` channel (redundant with defaults)

### Dependencies
```yaml
dependencies:
  # Language runtimes
  - python=3.10.6
  - r-base=4.5.1

  # Core bioinformatics tools
  - genometools-genometools=1.6.6
  - ltr_retriever=3.0.4
  - tesorter=1.5.1
  - clustalw=2.1

  # Python packages
  - numpy=2.2.*
  - pyfaidx

  # R visualization packages
  - r-ggplot2
  - r-viridis
  - r-hrbrthemes
  - r-rideogram
  - cairo  # Graphics backend
```

**Total**: 13 explicit dependencies (vs. 23 before)
**Reduction**: 43% smaller

---

## What Gets Pulled Automatically

These are transitive dependencies (do NOT list explicitly):
- perl=5.* (via ltr_retriever)
- perl-threaded (via ltr_retriever)
- vsearch (via ltr_retriever)
- cd-hit (via ltr_retriever)
- hmmer (via tesorter)
- repeatmasker (via ltr_retriever)
- rmblast (via repeatmasker)
- biopython (via ltr_retriever/tesorter)
- All R dependencies (via r-ggplot2, r-viridis, etc.)

---

## Risks & Mitigations

### Risk 1: Transitive dependency version conflicts
**Mitigation**: Lock file will freeze ALL versions

### Risk 2: LTR_retriever needs specific Perl
**Mitigation**: ltr_retriever package declares correct Perl version

### Risk 3: R package dependency hell
**Mitigation**: Pin r-base, let conda resolve R packages

### Risk 4: Platform-specific binaries
**Mitigation**: Explicit platform specification in lock file

---

## Testing Strategy

### Phase 1: Create clean environment
```bash
conda env create -f MegaLTR.clean.yml -n MegaLTR-test
```

### Phase 2: Verify tools
```bash
conda activate MegaLTR-test
python --version
gt --version
LTR_retriever -h
TEsorter -h
Rscript --version
```

### Phase 3: Run minimal test
```bash
bash MegaLTR.sh -A 2 -F test.fna -P test -t 2
```

### Phase 4: Generate lock file
```bash
conda env export -n MegaLTR-test > MegaLTR.lock.yml
```

---

## Summary

**Removed**: 10 packages (perl-bioperl, perl-text-soundex, pthread-stubs, gzip, etc.)
**Kept**: 13 explicit dependencies
**Transitive**: ~171 packages (pulled automatically)

**Benefits**:
- Cleaner, more maintainable
- Faster environment creation
- Less chance of conflicts
- Easier to understand what's actually needed

**No Changes**:
- Scientific logic unchanged
- All tools available
- Same versions (where it matters)
