#!/usr/bin/env python3
"""
merge_retriever_tesorter.py - Merge LTR_retriever pass.list with TEsorter classification

This script creates a 37-column TSV output compatible with classification_NEW_LTR_2.py
when LTRDIGEST is unavailable. It parses LTR_retriever pass.list and TEsorter results.

Usage:
    python3 merge_retriever_tesorter.py <pass_list> <tesorter_ltr> <output_file>

Output format (37 columns to match LTRDIGEST + TEsorter_Digest.pl output):
    1: LTR-RT id (chr_start_end)
    2: Pseudomolecules/scaffolds (chromosome)
    3: LTR-RT start
    4: LTR-RT end
    5: LTR-RT length
    6: lLTR start
    7: lLTR end
    8: lLTR length
    9: rLTR start
    10: rLTR end
    11: rLTR length
    12: lTSD start
    13: lTSD end
    14: lTSD sequence
    15: rTSD start
    16: rTSD end
    17: rTSD sequence
    18: PPT start (empty when unknown)
    19: PPT end
    20: PPT motif
    21: Strand
    22: PPT offset
    23: PBS start (empty when unknown)
    24: PBS end
    25: Strand
    26: tRNA id
    27: tRNA motif
    28: PBS offset
    29: tRNA offset
    30: PBS/tRNA
    31: (empty - spacer)
    32: Class
    33: Superfamily
    34: Clade
    35: Complete
    36: Strand
    37: Domains
"""

import sys
import os
import re

def parse_pass_list(filename):
    """Parse LTR_retriever pass.list file

    pass.list format (12 columns):
    0: LTR_loc (chr:start..end)
    1: Category (pass)
    2: Motif (motif:TGCA)
    3: TSD (TSD:XXXXX)
    4: 5_TSD (start..end)
    5: 3_TSD (start..end)
    6: Internal (IN:start..end)
    7: Identity
    8: Strand
    9: SuperFamily
    10: TE_type
    11: Insertion_Time
    """
    elements = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) < 10:
                continue

            # Parse LTR location (chr:start..end)
            ltr_loc = parts[0]
            match = re.match(r'(\S+):(\d+)\.\.(\d+)', ltr_loc)
            if not match:
                continue

            chrom = match.group(1)
            ltr_start = int(match.group(2))
            ltr_end = int(match.group(3))
            ltr_length = ltr_end - ltr_start + 1

            # Parse TSD info
            tsd_5_raw = parts[4]  # 5_TSD (start..end)
            tsd_3_raw = parts[5]  # 3_TSD (start..end)
            tsd_seq = parts[3].replace('TSD:', '') if parts[3].startswith('TSD:') else ''

            # Parse 5' TSD coordinates
            tsd_5_match = re.match(r'(\d+)\.\.(\d+)', tsd_5_raw)
            if tsd_5_match:
                tsd_5_start = int(tsd_5_match.group(1))
                tsd_5_end = int(tsd_5_match.group(2))
            else:
                tsd_5_start = tsd_5_end = 0

            # Parse 3' TSD coordinates
            tsd_3_match = re.match(r'(\d+)\.\.(\d+)', tsd_3_raw)
            if tsd_3_match:
                tsd_3_start = int(tsd_3_match.group(1))
                tsd_3_end = int(tsd_3_match.group(2))
            else:
                tsd_3_start = tsd_3_end = 0

            # Parse Internal region (IN:start..end)
            internal_raw = parts[6]
            internal_match = re.match(r'IN:(\d+)\.\.(\d+)', internal_raw)
            if internal_match:
                internal_start = int(internal_match.group(1))
                internal_end = int(internal_match.group(2))
            else:
                internal_start = ltr_start + 100
                internal_end = ltr_end - 100

            # Calculate LTR coordinates from internal region
            # Left LTR: from ltr_start to internal_start - 1
            # Right LTR: from internal_end + 1 to ltr_end
            lltr_start = ltr_start
            lltr_end = internal_start - 1
            lltr_length = lltr_end - lltr_start + 1

            rltr_start = internal_end + 1
            rltr_end = ltr_end
            rltr_length = rltr_end - rltr_start + 1

            # Other fields
            identity = parts[7] if len(parts) > 7 else '0.95'
            strand = parts[8] if len(parts) > 8 else '+'
            superfamily = parts[9] if len(parts) > 9 else 'unknown'
            te_type = parts[10] if len(parts) > 10 else 'LTR'

            elements.append({
                'id': ltr_loc,
                'chrom': chrom,
                'ltr_start': ltr_start,
                'ltr_end': ltr_end,
                'ltr_length': ltr_length,
                'lltr_start': lltr_start,
                'lltr_end': lltr_end,
                'lltr_length': lltr_length,
                'rltr_start': rltr_start,
                'rltr_end': rltr_end,
                'rltr_length': rltr_length,
                'tsd_5_start': tsd_5_start,
                'tsd_5_end': tsd_5_end,
                'tsd_seq': tsd_seq,
                'tsd_3_start': tsd_3_start,
                'tsd_3_end': tsd_3_end,
                'strand': strand,
                'superfamily': superfamily,
                'te_type': te_type,
                'identity': identity
            })

    return elements

def parse_tesorter(filename):
    """Parse TEsorter classification file

    TEsorter .cls.tsv format:
    0: #TE (sequence ID)
    1: Order
    2: Superfamily
    3: Clade
    4: Complete (yes/no/unknown)
    5: Strand
    6: Domains
    """
    classifications = {}
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if len(parts) < 2:
                continue

            seq_id = parts[0]
            # Extract base ID - handle formats like "chr:start..end#LTR/Copia"
            base_id = seq_id.split('#')[0] if '#' in seq_id else seq_id

            classifications[base_id] = {
                'order': parts[1] if len(parts) > 1 else 'LTR',
                'superfamily': parts[2] if len(parts) > 2 else 'unknown',
                'clade': parts[3] if len(parts) > 3 else 'unknown',
                'complete': parts[4] if len(parts) > 4 else 'unknown',
                'strand': parts[5] if len(parts) > 5 else '+',
                'domains': parts[6] if len(parts) > 6 else ''
            }

    return classifications

def merge_data(pass_list_elements, tesorter_data, output_file):
    """Merge pass.list and TEsorter data into 37-column format"""
    merged_count = 0

    with open(output_file, 'w') as out:
        for elem in pass_list_elements:
            # Find matching TEsorter classification
            tesorter_info = None

            # Try exact match first
            if elem['id'] in tesorter_data:
                tesorter_info = tesorter_data[elem['id']]
            else:
                # Try partial match
                for te_id, te_data in tesorter_data.items():
                    if elem['id'] in te_id or te_id in elem['id']:
                        tesorter_info = te_data
                        break
                    # Also try matching by coordinates
                    te_match = re.search(r'(\d+)\.\.(\d+)', te_id)
                    if te_match:
                        te_start = int(te_match.group(1))
                        te_end = int(te_match.group(2))
                        if abs(te_start - elem['ltr_start']) < 100 and abs(te_end - elem['ltr_end']) < 100:
                            tesorter_info = te_data
                            break

            # Default values if no TEsorter match
            if tesorter_info is None:
                tesorter_info = {
                    'order': 'LTR',
                    'superfamily': elem['superfamily'] if elem['superfamily'] != 'unknown' else 'unknown',
                    'clade': 'unknown',
                    'complete': 'unknown',
                    'strand': elem['strand'],
                    'domains': ''
                }

            # Create element ID in expected format: chr_start_end
            elem_id = f"{elem['chrom']}_{elem['ltr_start']}_{elem['ltr_end']}"

            # Build 37-column output row
            # Classification script expects specific numeric columns
            row = [
                elem_id,                           # 1: LTR-RT id
                elem['chrom'],                     # 2: Pseudomolecules/scaffolds
                str(elem['ltr_start']),            # 3: LTR-RT start
                str(elem['ltr_end']),              # 4: LTR-RT end
                str(elem['ltr_length']),           # 5: LTR-RT length
                str(elem['lltr_start']),           # 6: lLTR start
                str(elem['lltr_end']),             # 7: lLTR end
                str(elem['lltr_length']),          # 8: lLTR length
                str(elem['rltr_start']),           # 9: rLTR start
                str(elem['rltr_end']),             # 10: rLTR end
                str(elem['rltr_length']),          # 11: rLTR length
                str(elem['tsd_5_start']),          # 12: lTSD start
                str(elem['tsd_5_end']),            # 13: lTSD end
                elem['tsd_seq'],                   # 14: lTSD sequence
                str(elem['tsd_3_start']),          # 15: rTSD start
                str(elem['tsd_3_end']),            # 16: rTSD end
                elem['tsd_seq'],                   # 17: rTSD sequence
                '',                                # 18: PPT start (empty - unknown without LTRDIGEST)
                '',                                # 19: PPT end
                '',                                # 20: PPT motif
                elem['strand'],                    # 21: Strand
                '',                                # 22: PPT offset
                '',                                # 23: PBS start (empty - unknown without LTRDIGEST)
                '',                                # 24: PBS end
                elem['strand'],                    # 25: Strand
                '',                                # 26: tRNA id
                '',                                # 27: tRNA motif
                '',                                # 28: PBS offset
                '',                                # 29: tRNA offset
                '',                                # 30: PBS/tRNA
                '',                                # 31: (empty spacer)
                tesorter_info['order'],            # 32: Class
                f"Nonautonomous:{tesorter_info['superfamily']}",  # 33: Superfamily
                tesorter_info['clade'],            # 34: Clade
                tesorter_info['complete'],         # 35: Complete
                tesorter_info['strand'],           # 36: Strand
                tesorter_info['domains']           # 37: Domains
            ]

            out.write('\t'.join(row) + '\n')
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
        print(f"Error: pass.list file not found: {pass_list_file}", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(tesorter_file):
        print(f"Error: TEsorter file not found: {tesorter_file}", file=sys.stderr)
        sys.exit(1)

    # Parse input files
    print(f"[merge_retriever_tesorter] Reading {pass_list_file}", file=sys.stderr)
    pass_list_elements = parse_pass_list(pass_list_file)
    print(f"[merge_retriever_tesorter] Found {len(pass_list_elements)} elements in pass.list", file=sys.stderr)

    print(f"[merge_retriever_tesorter] Reading {tesorter_file}", file=sys.stderr)
    tesorter_data = parse_tesorter(tesorter_file)
    print(f"[merge_retriever_tesorter] Found {len(tesorter_data)} TEsorter classifications", file=sys.stderr)

    # Merge and write output
    merged_count = merge_data(pass_list_elements, tesorter_data, output_file)
    print(f"[merge_retriever_tesorter] Successfully merged {merged_count} LTR elements", file=sys.stderr)
    print(f"[merge_retriever_tesorter] Output written to: {output_file}", file=sys.stderr)

if __name__ == '__main__':
    main()
