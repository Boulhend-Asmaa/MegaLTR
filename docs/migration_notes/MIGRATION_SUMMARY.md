# Perl to Python Migration Summary

## Overview
This document summarizes the migration of Perl scripts to Python in the MegaLTR pipeline to fix bugs and improve performance.

## Migrated Scripts

### 1. estimate_K.pl → estimate_K.py
- **Location**: `bin/RUN/estimate_K.py`
- **Purpose**: Calculate evolutionary distances (Kimura and Tajima-Nei) and insertion times for LTR retrotransposons
- **Bugs Fixed**: Performance bottleneck, inefficient Perl implementation
- **Status**: ✅ Tested and validated
- **Performance**: Significantly faster than Perl version

### 2. get-TE-within-gene.pl → get-TE-within-gene.py
- **Location**: `bin/RUN/get-TE-within-gene.py`
- **Purpose**: Identify LTR retrotransposons located within gene boundaries
- **Bugs Fixed**: Performance issues with large GFF files
- **Status**: ✅ Tested and validated

### 3. get-TE-near-gene-*.pl (4 scripts) → get-TE-near-gene.py (unified)
- **Location**: `bin/RUN/get-TE-near-gene.py`
- **Original Scripts**:
  - `get-TE-near-gene-pluse+1k.pl`
  - `get-TE-near-gene-pluse-1k.pl`
  - `get-TE-near-gene-minuse1k.pl`
  - `get-TE-near-gene-minuse-1k.pl`
- **Purpose**: Find genes upstream/downstream of LTR elements
- **Bugs Fixed**: Duplicate code, inconsistent logic across 4 scripts
- **Improvement**: Unified into single script with mode parameter
- **Status**: ✅ Tested and validated

### 4. join_tables.py (replaces TEsorter_Digest.pl & TEsorterandtable_time.pl)
- **Location**: `bin/RUN/join_tables.py`
- **Original Scripts**:
  - `TEsorter_Digest.pl`
  - `TEsorterandtable_time.pl`
- **Purpose**: Join LTR tables from different sources
- **Bugs Fixed**: Inefficient nested loops (O(n²) complexity)
- **Status**: ✅ Tested and validated

### 5. print.pl → print_ltrdigest.py
- **Location**: `bin/RUN/print_ltrdigest.py`
- **Purpose**: Reformat LTRdigest CSV output by reordering columns
- **Bugs Fixed**:
  - ❌ Regex pattern `([\S|\s]+)` incorrect (pipe inside [] is literal, not OR)
  - Should be `(\S+)` or `(.+)` for "rest of line"
- **Status**: ✅ Tested and validated
- **MegaLTR.sh**: Line 323 updated to use Python version

### 6. No.pl → add_no_column.py
- **Location**: `bin/RUN/add_no_column.py`
- **Purpose**: Append "No" column to mark LTR-RTs outside gene boundaries
- **Bugs Fixed**:
  - ❌ Regex pattern `([\S|\s]+)` incorrect (same as print.pl)
  - ❌ Closes wrong file handle (`GFILE` instead of `PFILE`) - line 14
  - ❌ Takes 2 arguments but only uses 1 (`$processid` unused)
- **Status**: ✅ Tested and validated
- **MegaLTR.sh**: Line 442 updated to use Python version

### 7. checkfasta.pl → checkfasta.py
- **Location**: `bin/RUN/checkfasta.py`
- **Purpose**: Validate FASTA file format
- **Status**: ✅ Already migrated (pre-existing)

### 8. extractseq-id-start-end.pl → extractseq-id-start-end.py
- **Location**: `bin/RUN/extractseq-id-start-end.py`
- **Purpose**: Extract sequences by ID and coordinates
- **Status**: ✅ Already migrated (pre-existing)

## Bug Summary

### Critical Bugs Fixed
1. **No.pl** - File handle bug (closes wrong file) - could cause crashes
2. **No.pl** - Unused parameter indicates incomplete implementation
3. **print.pl** - Regex bug could cause data loss
4. **No.pl** - Regex bug could cause incorrect pattern matching

### Performance Improvements
1. **estimate_K.pl** - Major bottleneck, now significantly faster
2. **join_tables.py** - O(n²) → O(n) complexity improvement
3. **get-TE-near-gene.py** - 4 scripts unified into 1

## Testing

All migrated scripts have been tested with real data:
- Test directory: `test_python/`
- Test dataset: Arabidopsis thaliana chromosome NC_003070.9
- Results: ✅ All outputs match or exceed Perl versions
- Errors: None (only expected LAI warning for small dataset)

## Backup

Original Perl scripts backed up to: `backup_perl/`

## Files Modified

### Python Scripts Created
- `bin/RUN/estimate_K.py` (new)
- `bin/RUN/get-TE-within-gene.py` (new)
- `bin/RUN/get-TE-near-gene.py` (new)
- `bin/RUN/join_tables.py` (updated)
- `bin/RUN/print_ltrdigest.py` (new)
- `bin/RUN/add_no_column.py` (new)

### Shell Scripts Modified
- `MegaLTR.sh` (lines 323, 442 updated)

## Migration Complete

All critical Perl scripts actively used in the MegaLTR pipeline have been successfully migrated to Python with:
- ✅ All bugs fixed
- ✅ Performance improved
- ✅ Code unified and simplified
- ✅ Full test validation

**Date**: 2026-01-09
**Branch**: feat/perl-to-python
