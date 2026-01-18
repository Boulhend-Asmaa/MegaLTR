#!/usr/bin/env python3
"""
merge_retriever_tesorter.py - Merge LTR_retriever pass.list with TEsorter classification

This script merges data from LTR_retriever's pass.list file with TEsorter's
classification results when LTRDIGEST is unavailable.

Usage:
    python3 merge_retriever_tesorter.py <pass_list> <tesorter_ltr> <output_file>

Arguments:
    pass_list     - LTR_retriever pass.list file
    tesorter_ltr  - TEsorter classification file (LTR elements only)
    output_file   - Output TSV file with merged data

Output format (37 columns to match TEsorter_Digest.pl output):
    Columns 1-31: From LTR_retriever pass.list
    Columns 32-37: From TEsorter classification + placeholders
"""

import sys
import os
import re

def parse_pass_list(filename):
    """Parse LTR_retriever pass.list file"""
    elements = {}
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) < 2:
                continue
            # Extract element ID (first column)
            element_id = parts[0]
            elements[element_id] = parts
    return elements

def parse_tesorter(filename):
    """Parse TEsorter classification file"""
    classifications = {}
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) < 2:
                continue
            # TEsorter format: ID, Order, Superfamily, Clade, Complete, Strand, Domains
            seq_id = parts[0]
            # Extract the base ID (before any suffixes)
            # Format: chr:start..end or similar
            base_id = seq_id.split('#')[0] if '#' in seq_id else seq_id
            classifications[base_id] = {
                'order': parts[1] if len(parts) > 1 else 'unknown',
                'superfamily': parts[2] if len(parts) > 2 else 'unknown',
                'clade': parts[3] if len(parts) > 3 else 'unknown',
                'complete': parts[4] if len(parts) > 4 else 'unknown',
                'strand': parts[5] if len(parts) > 5 else '+',
                'domains': parts[6] if len(parts) > 6 else ''
            }
    return classifications

def merge_data(pass_list_data, tesorter_data, output_file):
    """Merge pass.list and TEsorter data into 37-column format"""
    merged_count = 0

    with open(output_file, 'w') as out:
        for element_id, pass_list_cols in pass_list_data.items():
            # Find matching TEsorter classification
            tesorter_info = None
            for te_id, te_data in tesorter_data.items():
                if element_id in te_id or te_id in element_id:
                    tesorter_info = te_data
                    break

            # Default values if no TEsorter match
            if tesorter_info is None:
                tesorter_info = {
                    'order': 'LTR',
                    'superfamily': 'unknown',
                    'clade': 'unknown',
                    'complete': 'unknown',
                    'strand': '+',
                    'domains': ''
                }

            # Build 37-column output
            # Columns 1-31 from pass.list (pad if necessary)
            output_cols = pass_list_cols[:31] if len(pass_list_cols) >= 31 else pass_list_cols + [''] * (31 - len(pass_list_cols))

            # Ensure we have exactly 31 columns from pass.list
            while len(output_cols) < 31:
                output_cols.append('')

            # Columns 32-37: TEsorter data
            # 32: Superfamily/Clade (family)
            output_cols.append(tesorter_info['clade'])
            # 33: Status (complete/incomplete)
            output_cols.append(tesorter_info['complete'])
            # 34: Strand
            output_cols.append(tesorter_info['strand'])
            # 35: Order
            output_cols.append(tesorter_info['order'])
            # 36: Superfamily
            output_cols.append(tesorter_info['superfamily'])
            # 37: Domains
            output_cols.append(tesorter_info['domains'])

            out.write('\t'.join(output_cols) + '\n')
            merged_count += 1

    return merged_count

def main():
    if len(sys.argv) != 4:
        print("Usage: python3 merge_retriever_tesorter.py <pass_list> <tesorter_ltr> <output_file>")
        print("  pass_list    - LTR_retriever pass.list file")
        print("  tesorter_ltr - TEsorter LTR classification file")
        print("  output_file  - Output TSV file")
        sys.exit(1)

    pass_list_file = sys.argv[1]
    tesorter_file = sys.argv[2]
    output_file = sys.argv[3]

    # Check input files exist
    if not os.path.exists(pass_list_file):
        print(f"Error: pass.list file not found: {pass_list_file}")
        sys.exit(1)

    if not os.path.exists(tesorter_file):
        print(f"Error: TEsorter file not found: {tesorter_file}")
        sys.exit(1)

    # Parse input files
    print(f"[merge_retriever_tesorter] Reading {pass_list_file}")
    pass_list_data = parse_pass_list(pass_list_file)
    print(f"[merge_retriever_tesorter] Found {len(pass_list_data)} elements in pass.list")

    print(f"[merge_retriever_tesorter] Reading {tesorter_file}")
    tesorter_data = parse_tesorter(tesorter_file)
    print(f"[merge_retriever_tesorter] Found {len(tesorter_data)} TEsorter classifications")

    # Merge and write output
    merged_count = merge_data(pass_list_data, tesorter_data, output_file)
    print(f"[merge_retriever_tesorter] Successfully merged {merged_count} LTR elements")
    print(f"[merge_retriever_tesorter] Output written to: {output_file}")

if __name__ == '__main__':
    main()
