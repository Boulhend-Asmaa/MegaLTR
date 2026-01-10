#!/bin/bash
# MegaLTR Environment Validation Script
# Verifies all required tools are available and functioning

echo "=== MegaLTR Environment Validation ==="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_tool() {
    local tool=$1
    local version_flag=$2
    local expected_pattern=$3

    echo -n "Checking $tool... "
    if command -v "$tool" &> /dev/null; then
        version_output=$($tool $version_flag 2>&1 || true)
        if [[ -n "$expected_pattern" ]] && ! echo "$version_output" | grep -qi "$expected_pattern"; then
            echo -e "${YELLOW}FOUND but unexpected version${NC}"
            echo "  Output: $version_output" | head -n 1
            echo "  Expected pattern: $expected_pattern"
            return 0  # Don't fail, just warn
        fi
        echo -e "${GREEN}OK${NC}"
        echo "  $version_output" | head -n 1
        return 0
    else
        echo -e "${RED}NOT FOUND${NC}"
        return 1
    fi
}

check_python_package() {
    local package=$1
    echo -n "Checking Python package $package... "
    if python -c "import $package" 2>/dev/null; then
        version=$(python -c "import $package; print($package.__version__)" 2>/dev/null || echo "unknown")
        echo -e "${GREEN}OK${NC} (version: $version)"
        return 0
    else
        echo -e "${RED}NOT FOUND${NC}"
        return 1
    fi
}

check_r_package() {
    local package=$1
    echo -n "Checking R package $package... "
    if Rscript -e "library($package)" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}NOT FOUND${NC}"
        return 1
    fi
}

# Track failures
FAILED=0

echo "--- Language Runtimes ---"
check_tool "python" "--version" "Python 3.10" || FAILED=$((FAILED+1))
check_tool "perl" "--version" "perl 5" || FAILED=$((FAILED+1))
check_tool "Rscript" "--version" "" || FAILED=$((FAILED+1))  # R 4.x is fine, don't enforce specific version
echo ""

echo "--- Core Bioinformatics Tools ---"
check_tool "gt" "--version" "GenomeTools" || FAILED=$((FAILED+1))
check_tool "LTR_retriever" "-h" "LTR_retriever" || FAILED=$((FAILED+1))
check_tool "TEsorter" "-h" "TEsorter" || FAILED=$((FAILED+1))
check_tool "clustalw" "-help" "CLUSTAL" || FAILED=$((FAILED+1))
check_tool "vsearch" "--version" "vsearch" || FAILED=$((FAILED+1))
check_tool "cd-hit" "-h" "CD-HIT" || FAILED=$((FAILED+1))
check_tool "hmmscan" "-h" "HMMER" || FAILED=$((FAILED+1))
echo ""

echo "--- Python Packages ---"
check_python_package "numpy" || FAILED=$((FAILED+1))
check_python_package "pyfaidx" || FAILED=$((FAILED+1))
check_python_package "Bio" || FAILED=$((FAILED+1))  # biopython
echo ""

echo "--- R Packages ---"
check_r_package "ggplot2" || FAILED=$((FAILED+1))
check_r_package "viridis" || FAILED=$((FAILED+1))
check_r_package "hrbrthemes" || FAILED=$((FAILED+1))
check_r_package "RIdeogram" || FAILED=$((FAILED+1))
echo ""

echo "--- Summary ---"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo "Environment is ready for MegaLTR pipeline."
    exit 0
else
    echo -e "${RED}$FAILED checks failed!${NC}"
    echo "Please review the environment setup."
    exit 1
fi
