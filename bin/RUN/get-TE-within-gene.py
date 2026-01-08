#!/usr/bin/env python3
"""
get-TE-within-gene.py - Identify LTR-RT gene chimera based on LTR-Retrotransposons localization

The script compares the gene start and end with the start and end of LTR-RT within the genome.
LTR-RT is considered a LTR-RT gene chimera if it is located within the gene start and end
coordinates provided by the gene annotation in the GFF files.

Python port of get-TE-within-gene.pl
"""

import sys
import re


def parse_tsv_line(line):
    """Parse a TSV line into fields (handles tab-separated fields)"""
    parts = line.strip().split('\t')
    if len(parts) >= 8:
        # Store first 7 fields individually, and rest as 8th field
        result = parts[:7]
        # Join remaining fields with tabs (field 8 onwards)
        result.append('\t'.join(parts[7:]))
        return result
    return None


def parse_gff_line(line):
    """Parse a GFF line into fields"""
    parts = line.strip().split('\t')
    if len(parts) >= 9:
        return parts
    return None


def main():
    if len(sys.argv) != 5:
        print("Usage: get-TE-within-gene.py <ltr_file> <gene_gff> <process_id> <output_dir>",
              file=sys.stderr)
        sys.exit(1)

    searchfile = sys.argv[1]  # LTR-RT TSV file
    searchfor = sys.argv[2]   # Gene annotation GFF file
    process_id = sys.argv[3]  # Process ID (unused in original script)
    out_dir = sys.argv[4]     # Output directory

    # Read LTR-RT data into array
    parray = []
    try:
        with open(searchfile, 'r') as pfile:
            for line in pfile:
                fields = parse_tsv_line(line)
                if fields and len(fields) == 8:
                    # Store all 8 fields (first 7 individual, 8th is rest)
                    parray.append(fields)
    except FileNotFoundError:
        print(f"Error: Cannot open LTR file {searchfile}", file=sys.stderr)
        sys.exit(1)

    # Open output file
    output_file = f"{out_dir}/LTR_inside_genes.table.2"
    try:
        with open(output_file, 'w') as outfile:
            # Process gene GFF file
            with open(searchfor, 'r') as gfile:
                for line in gfile:
                    fields = parse_gff_line(line)
                    if not fields or len(fields) < 9:
                        continue

                    contig = fields[0]
                    edta = fields[1]
                    region = fields[2]
                    start = int(fields[3])
                    end = int(fields[4])
                    all_field = fields[5]
                    all2 = fields[6]
                    all3 = fields[7]
                    all4 = fields[8]

                    # Compare against all LTR-RTs
                    for i, prow in enumerate(parray):
                        # Check if:
                        # 1. Same contig (prow[1] matches contig)
                        # 2. LTR start (prow[2]) is >= gene start
                        # 3. LTR end (prow[3]) is <= gene end
                        if (contig == prow[1] and
                            start <= int(prow[2]) and
                            end >= int(prow[3])):

                            # Print to stdout
                            print(f"{prow[0]}\t{prow[1]}\t{prow[2]}\t{prow[3]}\t"
                                  f"{prow[4]}\t{prow[5]}\t{prow[6]}\t{prow[7]}\t"
                                  f"Yes\t{region}\t{start}\t{end}\t"
                                  f"{all_field}\t{all2}\t{all3}\t{all4}")

                            # Print to output file
                            outfile.write(f"0\t{prow[0]}\tLTR-gene chimera\t"
                                        f"Inside the gene\t{prow[1]}\t{prow[2]}\t"
                                        f"{prow[3]}\t{prow[4]}\t{prow[5]}\t"
                                        f"{prow[6]}\t{prow[7]}\t{region}\t"
                                        f"{start}\t{end}\t{all_field}\t{all2}\t{all4}\n")

    except FileNotFoundError:
        print(f"Error: Cannot open gene file {searchfor}", file=sys.stderr)
        sys.exit(1)
    except IOError as e:
        print(f"Error: Cannot write to output file {output_file}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
