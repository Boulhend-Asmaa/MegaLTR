#!/bin/bash
#
# MegaLTR Phase 6 - Quick Testing Script
# Author: Asmaa Boulhend
# Date: 2026-01-15
#
# This script runs essential validation tests for Phase 6
# See PHASE6_TESTING_PROTOCOL.md for detailed instructions
#

set +e  # Don't exit on error (we want to report all test results)

# Detect Nextflow installation
if command -v nextflow > /dev/null 2>&1; then
    NEXTFLOW="nextflow"
elif [ -f "/home/asmaa/miniconda3/bin/nextflow" ]; then
    NEXTFLOW="/home/asmaa/miniconda3/bin/nextflow"
elif [ -f "$HOME/miniconda3/bin/nextflow" ]; then
    NEXTFLOW="$HOME/miniconda3/bin/nextflow"
elif [ -f "./nextflow" ]; then
    NEXTFLOW="./nextflow"
else
    NEXTFLOW="nextflow"  # Will fail gracefully in tests
fi

echo "============================================================"
echo " MegaLTR Phase 6 - Quick Validation Suite"
echo "============================================================"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASS=0
FAIL=0
TOTAL=0

# Function to report test result
report_test() {
    TOTAL=$((TOTAL + 1))
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
        FAIL=$((FAIL + 1))
    fi
    echo ""
}

# ============================================================================
# TEST 1: Syntax Validation
# ============================================================================
echo "TEST 1: Syntax Validation"
echo "-------------------------"

# Check help message
if $NEXTFLOW run main.nf --help > /dev/null 2>&1; then
    report_test 0 "Workflow syntax valid"
else
    report_test 1 "Workflow syntax invalid"
fi

# ============================================================================
# TEST 2: File Presence Check
# ============================================================================
echo "TEST 2: File Presence Check"
echo "----------------------------"

# Check critical files
FILES=(
    "main.nf"
    "nextflow.config"
    "MegaLTR.clean.yml"
    "bin/RUN/smart_split_tsv.py"
    "Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna"
    "Data_for_test/Arabidopsis_thaliana.gff"
)

MISSING=0
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Missing: $file${NC}"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -eq 0 ]; then
    report_test 0 "All required files present"
else
    report_test 1 "$MISSING required files missing"
fi

# ============================================================================
# TEST 3: Phase 3 Python Scripts
# ============================================================================
echo "TEST 3: Phase 3 Python Scripts"
echo "-------------------------------"

SCRIPTS=(
    "checkfasta.py"
    "replaceIDs.py"
    "modifyGFF.py"
    "classification_NEW_LTR_2.py"
    "super_familly_stat.py"
    "LTR_Seq_threads.py"
    "get_region.py"
    "counter.py"
    "figure_legend.py"
    "smart_split_tsv.py"
)

SCRIPT_MISSING=0
for script in "${SCRIPTS[@]}"; do
    if [ ! -f "bin/RUN/$script" ]; then
        echo -e "${RED}Missing: bin/RUN/$script${NC}"
        SCRIPT_MISSING=$((SCRIPT_MISSING + 1))
    elif [ ! -x "bin/RUN/$script" ]; then
        echo -e "${YELLOW}Warning: bin/RUN/$script not executable${NC}"
    fi
done

if [ $SCRIPT_MISSING -eq 0 ]; then
    report_test 0 "All 10 Python scripts present"
else
    report_test 1 "$SCRIPT_MISSING Python scripts missing"
fi

# ============================================================================
# TEST 4: Nextflow Installation
# ============================================================================
echo "TEST 4: Nextflow Installation"
echo "------------------------------"

if $NEXTFLOW -version > /dev/null 2>&1; then
    NF_VERSION=$($NEXTFLOW -version 2>&1 | head -1 | awk '{print $3}')
    echo "Nextflow version: $NF_VERSION"
    echo "Nextflow path: $NEXTFLOW"
    report_test 0 "Nextflow installed"
else
    report_test 1 "Nextflow not found"
fi

# ============================================================================
# TEST 5: Conda Environment
# ============================================================================
echo "TEST 5: Conda Environment"
echo "-------------------------"

if command -v conda > /dev/null 2>&1; then
    CONDA_VERSION=$(conda --version | awk '{print $2}')
    echo "Conda version: $CONDA_VERSION"

    # Check if MegaLTR env exists
    if conda env list | grep -q "MegaLTR"; then
        echo "MegaLTR conda environment exists"
        report_test 0 "Conda environment ready"
    else
        echo -e "${YELLOW}MegaLTR environment not found${NC}"
        echo "Run: conda env create -f MegaLTR.clean.yml"
        report_test 1 "Conda environment missing"
    fi
else
    report_test 1 "Conda not found"
fi

# ============================================================================
# TEST 6: Workflow Preview (Dry Run)
# ============================================================================
echo "TEST 6: Workflow Preview"
echo "------------------------"

if $NEXTFLOW run main.nf \
    --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \
    --gff Data_for_test/Arabidopsis_thaliana.gff \
    -preview > /tmp/nf_preview.log 2>&1; then

    # Count unique process names in preview
    # Note: Preview may not show all processes due to conditional execution
    PROCESS_COUNT=$(grep -oE "^\[-.*\] [A-Z_]+" /tmp/nf_preview.log | awk '{print $NF}' | sort -u | wc -l)
    echo "Unique processes found: $PROCESS_COUNT"

    # Check if preview ran successfully (at least 10 processes should be visible)
    if [ $PROCESS_COUNT -ge 10 ]; then
        report_test 0 "Workflow preview successful ($PROCESS_COUNT unique processes)"
    else
        report_test 1 "Workflow preview incomplete ($PROCESS_COUNT processes)"
    fi
else
    report_test 1 "Workflow preview failed"
fi

# ============================================================================
# TEST 7: Phase 5 Integration Check
# ============================================================================
echo "TEST 7: Phase 5 Integration"
echo "----------------------------"

# Check smart_split_tsv.py is referenced in main.nf
if grep -q "smart_split_tsv.py" main.nf; then
    echo "smart_split_tsv.py referenced in workflow"

    # Check SPLIT_COORDINATES process exists
    if grep -q "process SPLIT_COORDINATES" main.nf; then
        echo "SPLIT_COORDINATES process defined"
        report_test 0 "Phase 5 integration verified"
    else
        report_test 1 "SPLIT_COORDINATES process missing"
    fi
else
    report_test 1 "smart_split_tsv.py not referenced"
fi

# ============================================================================
# TEST 8: Phase 4 Integration Check
# ============================================================================
echo "TEST 8: Phase 4 Integration"
echo "----------------------------"

# Check MegaLTR.clean.yml is referenced
CONDA_REFS=$(grep -c "MegaLTR.clean.yml" nextflow.config)
echo "Conda environment references: $CONDA_REFS"

if [ $CONDA_REFS -ge 3 ]; then
    report_test 0 "Phase 4 integration verified ($CONDA_REFS profiles)"
else
    report_test 1 "Phase 4 integration incomplete"
fi

# ============================================================================
# Summary
# ============================================================================
echo "============================================================"
echo " Test Summary"
echo "============================================================"
echo -e "Total tests: $TOTAL"
echo -e "${GREEN}Passed: $PASS${NC}"
echo -e "${RED}Failed: $FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run full workflow test:"
    echo "   nextflow run main.nf --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna --gff Data_for_test/Arabidopsis_thaliana.gff -profile conda"
    echo ""
    echo "2. See PHASE6_TESTING_PROTOCOL.md for complete validation"
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo ""
    echo "Please review failed tests above"
    echo "See PHASE6_TESTING_PROTOCOL.md for troubleshooting"
    exit 1
fi
