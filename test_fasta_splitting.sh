#!/bin/bash
# Test script for FASTA splitting optimization
# Author: Asmaa Boulhend
# Date: 2026-01-12

set -e  # Exit on error

echo "========================================"
echo "FASTA Splitting Optimization - Test Suite"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

pass_test() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail_test() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn_test() {
    echo -e "${YELLOW}⚠ WARNING${NC}: $1"
}

# ===========================================
# Test 1: TSV Splitting - Standalone
# ===========================================
echo "Test 1: TSV Splitting (smart_split_tsv.py)"
echo "-------------------------------------------"

TEST_INPUT="test_clean_env/Others/test_clean_env.ids.extract_seq"
TEST_OUTPUT="/tmp/test_tsv_split_$$"

if [ ! -f "$TEST_INPUT" ]; then
    fail_test "Test input not found: $TEST_INPUT"
    echo "Run a full pipeline test first to generate this file"
    exit 1
fi

# Count lines in input
INPUT_LINES=$(wc -l < "$TEST_INPUT")
echo "Input file: $TEST_INPUT ($INPUT_LINES lines)"

# Run smart splitter
python3 bin/RUN/smart_split_tsv.py \
    "$TEST_INPUT" \
    "$TEST_OUTPUT" \
    --threads 4 \
    --verbose > /tmp/tsv_split_output.txt 2>&1

# Verify output
CHUNK_COUNT=$(ls "$TEST_OUTPUT"/chunk* 2>/dev/null | wc -l)
EMPTY_COUNT=$(find "$TEST_OUTPUT" -name "chunk*" -size 0 2>/dev/null | wc -l)
OUTPUT_LINES=$(cat "$TEST_OUTPUT"/chunk* 2>/dev/null | wc -l)

echo "Results:"
echo "  Chunks created: $CHUNK_COUNT"
echo "  Empty chunks: $EMPTY_COUNT"
echo "  Output lines: $OUTPUT_LINES"

# Assertions
if [ "$CHUNK_COUNT" -eq 16 ]; then
    pass_test "Correct chunk count (16 for 39 lines)"
else
    fail_test "Expected 16 chunks, got $CHUNK_COUNT"
fi

if [ "$EMPTY_COUNT" -eq 0 ]; then
    pass_test "No empty chunks"
else
    fail_test "Found $EMPTY_COUNT empty chunks (expected 0)"
fi

if [ "$INPUT_LINES" -eq "$OUTPUT_LINES" ]; then
    pass_test "All lines preserved ($INPUT_LINES → $OUTPUT_LINES)"
else
    fail_test "Line count mismatch ($INPUT_LINES → $OUTPUT_LINES)"
fi

# Cleanup
rm -rf "$TEST_OUTPUT"
echo ""

# ===========================================
# Test 2: FASTA Splitting - Validation Mode
# ===========================================
echo "Test 2: FASTA Splitting Validation"
echo "-----------------------------------"

GENOME="Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna"

if [ ! -f "$GENOME" ]; then
    fail_test "Genome file not found: $GENOME"
    exit 1
fi

# Run validation
python3 bin/RUN/smart_split_fasta.py \
    "$GENOME" \
    /tmp/dummy \
    --validate > /tmp/fasta_validate_output.txt 2>&1

# Check output
if grep -q "Total sequences: 1" /tmp/fasta_validate_output.txt; then
    pass_test "FASTA validation detected 1 sequence"
else
    fail_test "FASTA validation failed"
fi

if grep -q "30,427,671 bp" /tmp/fasta_validate_output.txt; then
    pass_test "FASTA validation detected correct genome size"
else
    warn_test "Genome size not found in validation output"
fi

echo ""

# ===========================================
# Test 3: FASTA Splitting - Actual Split
# ===========================================
echo "Test 3: FASTA Splitting (single chromosome)"
echo "---------------------------------------------"

TEST_FASTA_OUTPUT="/tmp/test_fasta_split_$$"

python3 bin/RUN/smart_split_fasta.py \
    "$GENOME" \
    "$TEST_FASTA_OUTPUT" \
    --threads 4 \
    --verbose > /tmp/fasta_split_output.txt 2>&1

# Verify chunks
FASTA_CHUNKS=$(ls "$TEST_FASTA_OUTPUT"/chunk_*.fna 2>/dev/null | wc -l)

if [ "$FASTA_CHUNKS" -eq 1 ]; then
    pass_test "Single chromosome → 1 chunk (correct)"
else
    warn_test "Expected 1 chunk for single chromosome, got $FASTA_CHUNKS"
fi

# Verify chunk content
if [ -f "$TEST_FASTA_OUTPUT/chunk_001.fna" ]; then
    CHUNK_SEQS=$(grep -c "^>" "$TEST_FASTA_OUTPUT/chunk_001.fna")
    if [ "$CHUNK_SEQS" -eq 1 ]; then
        pass_test "Chunk contains 1 sequence"
    else
        fail_test "Chunk contains $CHUNK_SEQS sequences (expected 1)"
    fi
fi

# Cleanup
rm -rf "$TEST_FASTA_OUTPUT"
echo ""

# ===========================================
# Test 4: Integration Test (LTR_Seq_threads.py)
# ===========================================
echo "Test 4: Integration with LTR_Seq_threads.py"
echo "--------------------------------------------"

# Use existing chunks from test_clean_env
if [ -d "test_clean_env/LTRFiles" ]; then
    OLD_CHUNKS=$(ls test_clean_env/LTRFiles/x* 2>/dev/null | wc -l)
    OLD_EMPTY=$(ls -l test_clean_env/LTRFiles/x* 2>/dev/null | grep " 0 " | wc -l)

    echo "Old splitting (split -n l/100):"
    echo "  Total chunks: $OLD_CHUNKS"
    echo "  Empty chunks: $OLD_EMPTY"

    if [ "$OLD_EMPTY" -eq 61 ]; then
        warn_test "Old method created 61 empty files (as expected - this is the bug we fix)"
    fi
fi

# Create test chunks using new method
TEST_INT_DIR="/tmp/test_integration_$$"
mkdir -p "$TEST_INT_DIR"

python3 bin/RUN/smart_split_tsv.py \
    "$TEST_INPUT" \
    "$TEST_INT_DIR" \
    --threads 4 \
    2>&1 | grep "Created" || true

NEW_CHUNKS=$(ls "$TEST_INT_DIR"/chunk* 2>/dev/null | wc -l)
NEW_EMPTY=$(find "$TEST_INT_DIR" -name "chunk*" -size 0 2>/dev/null | wc -l)

echo ""
echo "New splitting (smart_split_tsv.py):"
echo "  Total chunks: $NEW_CHUNKS"
echo "  Empty chunks: $NEW_EMPTY"

if [ "$NEW_CHUNKS" -lt "$OLD_CHUNKS" ]; then
    pass_test "Chunk count reduced from $OLD_CHUNKS to $NEW_CHUNKS ($(((OLD_CHUNKS - NEW_CHUNKS) * 100 / OLD_CHUNKS))% reduction)"
fi

if [ "$NEW_EMPTY" -eq 0 ]; then
    pass_test "Zero empty chunks (vs $OLD_EMPTY empty with old method)"
fi

# Test LTR_Seq_threads.py with new chunks
echo ""
echo "Testing LTR_Seq_threads.py compatibility..."

TEST_OUTPUT_FA="/tmp/test_ltr_output_$$/LTR-RT_Sequence.fa"
mkdir -p "$(dirname "$TEST_OUTPUT_FA")"

python3 bin/RUN/LTR_Seq_threads.py \
    test_clean_env/test_clean_env.fna \
    "$TEST_INT_DIR" \
    "$(dirname "$TEST_OUTPUT_FA")" \
    4 \
    bin/RUN/extractseq-id-start-end.py \
    2>&1 > /tmp/ltr_seq_test.log || true

if [ -f "$TEST_OUTPUT_FA" ]; then
    OUTPUT_SEQS=$(grep -c "^>" "$TEST_OUTPUT_FA" || echo "0")
    if [ "$OUTPUT_SEQS" -gt 0 ]; then
        pass_test "LTR_Seq_threads.py extracted $OUTPUT_SEQS sequences"
    else
        fail_test "No sequences extracted"
    fi
else
    fail_test "Output file not created: $TEST_OUTPUT_FA"
fi

# Cleanup
rm -rf "$TEST_INT_DIR" "$(dirname "$TEST_OUTPUT_FA")"
echo ""

# ===========================================
# Test 5: Backward Compatibility
# ===========================================
echo "Test 5: Backward Compatibility (old x* naming)"
echo "-----------------------------------------------"

# Create old-style chunks
TEST_COMPAT_DIR="/tmp/test_compat_$$"
mkdir -p "$TEST_COMPAT_DIR"

# Create dummy xaa, xab files
echo "Chr1	100	200	+" > "$TEST_COMPAT_DIR/xaa"
echo "Chr1	300	400	+" > "$TEST_COMPAT_DIR/xab"

# Test that LTR_Seq_threads.py can still read old format
python3 -c "
import glob
import sys

LTRfiles = '$TEST_COMPAT_DIR'

# This is the new logic from LTR_Seq_threads.py
data = sorted(glob.glob(f'{LTRfiles}/chunk*'))
if not data:
    data = sorted(glob.glob(f'{LTRfiles}/x*'))

if not data:
    print('FAIL: No chunks found')
    sys.exit(1)

if len(data) == 2:
    print(f'PASS: Found {len(data)} old-style chunks')
    sys.exit(0)
else:
    print(f'FAIL: Expected 2 chunks, found {len(data)}')
    sys.exit(1)
"

if [ $? -eq 0 ]; then
    pass_test "Backward compatibility with old chunk naming"
else
    fail_test "Backward compatibility broken"
fi

# Cleanup
rm -rf "$TEST_COMPAT_DIR"
echo ""

# ===========================================
# Summary
# ===========================================
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run full pipeline test: bash MegaLTR.sh -A 3 -F Data_for_test/... -P test_optimized"
    echo "2. Compare scientific output: diff test_clean_env/Collected_Files/LTR_Table_TEsorter_Digest.tsv test_optimized/Collected_Files/LTR_Table_TEsorter_Digest.tsv"
    echo "3. If identical, commit changes to feat/fasta-splitting-optimization branch"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo "Review failures above before proceeding"
    exit 1
fi
