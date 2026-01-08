#!/usr/bin/env python3
"""
estimate_K.py - Calculate evolutionary distance (K) between LTR sequences
Estimates LTR-RT insertion time using Kimura and Tajima-Nei methods
Python port of estimate_K.pl from REannotate program
"""

import sys
import math
import re


def align2K(align_file, rate_of_evolution):
    """Parse ClustalW alignment file and calculate distances"""

    # Read all lines from alignment file
    with open(align_file, 'r') as f:
        lines = f.readlines()

    # Find the offset (number of header lines before alignment)
    clustalw_offset = 0
    while clustalw_offset < len(lines) and not re.search(r"(5'|3')", lines[clustalw_offset]):
        clustalw_offset += 1

    # Extract LTR1 (5') and LTR2 (3') sequence lines
    ltr1_lines = [line for line in lines if "5'" in line]
    ltr2_lines = [line for line in lines if "3'" in line]

    # Extract just the sequence parts (remove identifiers)
    ltr1_seqs = []
    ltr2_seqs = []

    for line in ltr1_lines:
        match = re.search(r'^\S+\s+([\w-]+)\s*$', line.strip())
        if match:
            ltr1_seqs.append(match.group(1))

    for line in ltr2_lines:
        match = re.search(r'^\S+\s+([\w-]+)\s*$', line.strip())
        if match:
            ltr2_seqs.append(match.group(1))

    # Extract consensus lines (every 4th line after offset)
    consensus_lines = []
    for line_num in range(1, len(ltr1_seqs) + 1):
        idx = (clustalw_offset - 2) + 4 * line_num
        if idx < len(lines):
            consensus_line = lines[idx].strip()
            # Keep only the characters that correspond to the sequences
            num_sites = len(ltr1_seqs[line_num - 1])
            consensus_line = consensus_line[-num_sites:] if len(consensus_line) >= num_sites else consensus_line
            consensus_lines.append(consensus_line)

    # Concatenate all sequence fragments
    ltr1 = ''.join(ltr1_seqs)
    ltr2 = ''.join(ltr2_seqs)
    consensus = ''.join(consensus_lines)

    return get_distances(ltr1, ltr2, consensus, rate_of_evolution)


def get_distances(seq1, seq2, consensus, rate_of_evolution):
    """Calculate Kimura and Tajima-Nei distances"""

    # Initialize counters
    num_compared_sites = 0
    transitions = 0
    transversions = 0
    indels = 0
    acgt_content = [0, 0, 0, 0]  # A, C, G, T
    acgt_pairs = {"AC": 0, "AG": 0, "AT": 0, "CG": 0, "CT": 0, "GT": 0}

    # Find initial and final sites (skip leading/trailing gaps)
    initial_site = 0
    while initial_site < len(seq1) and (seq1[initial_site] == '-' or seq2[initial_site] == '-'):
        initial_site += 1

    final_site = len(consensus) - 1
    while final_site >= 0 and (seq1[final_site] == '-' or seq2[final_site] == '-'):
        final_site -= 1

    num_compared_sites = final_site - initial_site + 1

    # Count differences
    last_indel_site = initial_site - 1

    for site in range(initial_site, final_site + 1):
        bases_at_site = seq1[site] + seq2[site]

        if consensus[site] == ' ':  # Different bases
            if '-' in bases_at_site:  # Indel
                if last_indel_site < site - 2:
                    indels += 1
                last_indel_site = site
                num_compared_sites -= 1
            elif re.match(r'[AC]', bases_at_site[0], re.I) and re.match(r'[AC]', bases_at_site[1], re.I):
                acgt_content[0] += 1
                acgt_content[1] += 1
                acgt_pairs["AC"] += 1
                transversions += 1
            elif re.match(r'[AG]', bases_at_site[0], re.I) and re.match(r'[AG]', bases_at_site[1], re.I):
                acgt_content[0] += 1
                acgt_content[2] += 1
                acgt_pairs["AG"] += 1
                transitions += 1
            elif re.match(r'[AT]', bases_at_site[0], re.I) and re.match(r'[AT]', bases_at_site[1], re.I):
                acgt_content[0] += 1
                acgt_content[3] += 1
                acgt_pairs["AT"] += 1
                transversions += 1
            elif re.match(r'[CG]', bases_at_site[0], re.I) and re.match(r'[CG]', bases_at_site[1], re.I):
                acgt_content[1] += 1
                acgt_content[2] += 1
                acgt_pairs["CG"] += 1
                transversions += 1
            elif re.match(r'[CT]', bases_at_site[0], re.I) and re.match(r'[CT]', bases_at_site[1], re.I):
                acgt_content[1] += 1
                acgt_content[3] += 1
                acgt_pairs["CT"] += 1
                transitions += 1
            elif re.match(r'[GT]', bases_at_site[0], re.I) and re.match(r'[GT]', bases_at_site[1], re.I):
                acgt_content[2] += 1
                acgt_content[3] += 1
                acgt_pairs["GT"] += 1
                transversions += 1
        else:  # Identical bases
            if re.match(r'A', bases_at_site[0], re.I):
                acgt_content[0] += 2
            elif re.match(r'C', bases_at_site[0], re.I):
                acgt_content[1] += 2
            elif re.match(r'G', bases_at_site[0], re.I):
                acgt_content[2] += 2
            elif re.match(r'T', bases_at_site[0], re.I):
                acgt_content[3] += 2

    # Convert counts to frequencies
    acgt_freq = [count / (2 * num_compared_sites) for count in acgt_content]
    acgt_pair_freq = [acgt_pairs[key] / num_compared_sites for key in sorted(acgt_pairs.keys())]

    # Calculate K using Kimura's 2-parameter method
    K_Kimura, V_Kimura = get_K_Kimura(num_compared_sites, transitions, transversions)

    # Calculate K using Tajima and Nei's method
    K_TajimaNei, V_TajimaNei = get_K_TajimaNei(
        num_compared_sites,
        transitions + transversions,
        *acgt_pair_freq,
        acgt_freq
    )

    K_Ksd = math.sqrt(V_Kimura)
    K_TNsd = math.sqrt(V_TajimaNei)

    # Calculate time of divergence
    timeK = "NA"
    timeTN = "NA"
    timeKsd = "NA"

    if rate_of_evolution:
        timeTN = K_TajimaNei / (2 * rate_of_evolution)
        timeK = K_Kimura / (2 * rate_of_evolution)
        timeKsd = math.sqrt(
            (V_Kimura * num_compared_sites**2 + K_Kimura * num_compared_sites) /
            (2 * rate_of_evolution * num_compared_sites)**2
        )

    transitions_ratio = transitions / num_compared_sites
    transversions_ratio = transversions / num_compared_sites

    return f"{K_Kimura}\t{K_Ksd}\t{K_TajimaNei}\t{K_TNsd}\t{timeK}\t{timeKsd}\t{num_compared_sites}\t{transitions}\t{num_compared_sites}\t{transversions}\t{num_compared_sites}\t{timeTN}\t{transitions_ratio}\t{transversions_ratio}"


def get_K_Kimura(length, transitions, transversions):
    """Calculate K distance using Kimura's 2-parameter method"""

    P = transitions / length  # Proportion of transitions
    Q = transversions / length  # Proportion of transversions

    a = 1 / (1 - 2*P - Q)
    b = 1 / (1 - 2*Q)
    c = (a + b) / 2

    K = math.log(a) / 2 + math.log(b) / 4

    # Approximate sampling variance
    V = (P * a**2 + Q * c**2 - (a*P + c*Q)**2) / length

    return K, V


def get_K_TajimaNei(length, diffs, fAC, fAG, fAT, fCG, fCT, fGT, acgt_freq):
    """Calculate K distance using Tajima and Nei's method"""

    p = diffs / length  # Proportion of different sites

    # Create matrix of nucleotide pair frequencies
    acgt_pairs = [
        [0, fAC, fAG, fAT],
        [0, 0, fCG, fCT],
        [0, 0, 0, fGT]
    ]

    b1 = 1 - sum([f**2 for f in acgt_freq])

    h = 0
    for i in range(3):
        for j in range(i + 1, 4):
            if acgt_freq[i] and acgt_freq[j]:
                h += acgt_pairs[i][j]**2 / (2 * acgt_freq[i] * acgt_freq[j])

    b = (b1 + p**2 / h) / 2 if h else 1

    # K distance
    K = -b * math.log(1 - p / b) if b else 0

    # Approximate sampling variance
    V = b**2 * p * (1 - p) / ((b - p)**2 * length) if (b - p) != 0 else 0

    return K, V


def main():
    if len(sys.argv) != 3:
        print("Usage: estimate_K.py <alignment_file> <rate_of_evolution>", file=sys.stderr)
        sys.exit(1)

    align_file = sys.argv[1]
    rate_of_evolution = float(sys.argv[2])

    try:
        result = align2K(align_file, rate_of_evolution)
        print(result)

    except FileNotFoundError:
        print(f"Error: Cannot open alignment file {align_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
