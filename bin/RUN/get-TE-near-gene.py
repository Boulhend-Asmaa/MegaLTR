#!/usr/bin/env python3
"""
get-TE-near-gene.py - Find LTR-RTs near genes (upstream/downstream)

This script identifies LTR-RTs that are within a specified distance from genes,
considering strand orientation. It replaces four Perl scripts:
- get-TE-near-gene-pluse+1k.pl (upstream of + strand genes)
- get-TE-near-gene-pluse-1k.pl (downstream of + strand genes)
- get-TE-near-gene-minuse-1k.pl (downstream of - strand genes)
- get-TE-near-gene-minuse1k.pl (upstream of - strand genes)

Python port of get-TE-near-gene-*.pl scripts
"""

import sys


def parse_ltr_line(line):
    """Parse LTR data line into fields"""
    parts = line.strip().split('\t')
    if len(parts) >= 5:
        # Return first 4 fields individually, rest as 5th field
        result = parts[:4]
        result.append('\t'.join(parts[4:]))
        return result
    return None


def parse_gff_line(line):
    """Parse GFF line into fields"""
    parts = line.strip().split('\t')
    if len(parts) >= 9:
        return parts
    return None


def main():
    if len(sys.argv) != 6:
        print("Usage: get-TE-near-gene.py <ltr_file> <gene_gff> <up_distance> <down_distance> <mode>",
              file=sys.stderr)
        print("  mode: 'plus-upstream' | 'plus-downstream' | 'minus-upstream' | 'minus-downstream'",
              file=sys.stderr)
        sys.exit(1)

    searchfile = sys.argv[1]   # LTR-RT file
    searchfor = sys.argv[2]    # Gene annotation GFF file
    up_distance = int(sys.argv[3])    # Distance upstream
    down_distance = int(sys.argv[4])  # Distance downstream
    mode = sys.argv[5]         # Mode: which script to emulate

    # Read LTR-RT data into array
    parray = []
    try:
        with open(searchfile, 'r') as pfile:
            for line in pfile:
                fields = parse_ltr_line(line)
                if fields and len(fields) == 5:
                    ltr_id = fields[0]
                    chromosome = fields[1]
                    start = int(fields[2])
                    end = int(fields[3])
                    rest = fields[4]

                    # Calculate extended range (start-up, end+down)
                    extended_start = start - up_distance
                    extended_end = end + down_distance

                    parray.append([ltr_id, chromosome, start, end, rest,
                                  extended_start, extended_end])
    except FileNotFoundError:
        print(f"Error: Cannot open LTR file {searchfile}", file=sys.stderr)
        sys.exit(1)

    # Process gene GFF file
    try:
        with open(searchfor, 'r') as gfile:
            for line in gfile:
                fields = parse_gff_line(line)
                if not fields or len(fields) < 9:
                    continue

                contig = fields[0]
                edta = fields[1]
                region = fields[2]
                gene_start = int(fields[3])
                gene_end = int(fields[4])
                all_field = fields[5]
                strand = fields[6]
                all2 = fields[7]
                all3 = fields[8]

                # Compare against all LTR-RTs
                for prow in parray:
                    ltr_id = prow[0]
                    ltr_chr = prow[1]
                    ltr_start = prow[2]
                    ltr_end = prow[3]
                    ltr_rest = prow[4]
                    ltr_ext_start = prow[5]
                    ltr_ext_end = prow[6]

                    # Skip if different chromosomes
                    if contig != ltr_chr:
                        continue

                    # Check conditions based on mode
                    match = False
                    label = ""
                    distance = 0

                    if mode == 'plus-upstream':
                        # get-TE-near-gene-pluse+1k.pl
                        # Condition: parray[3] <= start && parray[6] >= end
                        # LTR end <= gene start AND (LTR end + down) >= gene end
                        if ltr_end <= gene_start and ltr_ext_end >= gene_end:
                            match = True
                            label = "Genes Upstream LTR"
                            distance = gene_start - ltr_end

                    elif mode == 'plus-downstream':
                        # get-TE-near-gene-pluse-1k.pl
                        # Condition: parray[3] <= start && parray[6] >= end
                        # BUT also: my $length = $start - $parray[$i][3];
                        # So: LTR end <= gene start AND (LTR end + down) >= gene end
                        # NOTE: This is the SAME condition as plus-upstream!
                        # The difference is the label and which script processes which strand
                        if ltr_end <= gene_start and ltr_ext_end >= gene_end:
                            match = True
                            label = "Genes Downstream LTR"
                            distance = gene_start - ltr_end

                    elif mode == 'minus-downstream':
                        # get-TE-near-gene-minuse-1k.pl
                        # Condition: parray[5] <= start && parray[2] >= end
                        # (LTR start - up) <= gene start AND LTR start >= gene end
                        if ltr_ext_start <= gene_start and ltr_start >= gene_end:
                            match = True
                            label = "Genes Downstream LTR"
                            distance = ltr_start - gene_end

                    elif mode == 'minus-upstream':
                        # get-TE-near-gene-minuse1k.pl (note: minuse1k, not pluse+1k)
                        # Condition: parray[5] <= start && parray[2] >= end
                        # (LTR start - up) <= gene start AND LTR start >= gene end
                        if ltr_ext_start <= gene_start and ltr_start >= gene_end:
                            match = True
                            label = "Genes Upstream LTR"
                            distance = ltr_start - gene_end

                    if match:
                        print(f"{ltr_id}\t{label}\t{ltr_chr}\t{ltr_start}\t{ltr_end}\t"
                              f"{ltr_rest}\t{region}\t{gene_start}\t{gene_end}\t"
                              f"{distance}\t{strand}\t{all3}")

    except FileNotFoundError:
        print(f"Error: Cannot open gene file {searchfor}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
