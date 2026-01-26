#!/usr/bin/env python3
"""
join_tables.py - Join two TSV files based on first column (ID)

This script performs a left join operation between two tab-separated files.
For each line in file2, it finds matching IDs in file1 and outputs the merged line.

Python port of TEsorter_Digest.pl and TEsorterandtable_time.pl
(both scripts have identical logic, just different regex patterns)
"""

import sys


def parse_line(line):
    """Parse a line into ID and rest of fields (preserves tabs/empty fields)"""
    # Remove only newline, keep tabs
    line = line.rstrip('\n\r')
    parts = line.split('\t', 1)
    if len(parts) >= 1:
        # Strip trailing/leading whitespace from ID (matches Perl \S+ behavior)
        id_field = parts[0].strip()
        rest = parts[1] if len(parts) > 1 else ""
        return id_field, rest
    return None, None


def main():
    if len(sys.argv) != 3:
        print("Usage: join_tables.py <file1> <file2>", file=sys.stderr)
        print("  Joins file2 with file1 based on matching first column (ID)", file=sys.stderr)
        sys.exit(1)

    file1 = sys.argv[1]
    file2 = sys.argv[2]

    # Read first file into array
    parray = []
    try:
        with open(file1, 'r') as f:
            for line in f:
                id_field, rest = parse_line(line)
                if id_field:
                    parray.append([id_field, rest])
    except FileNotFoundError:
        print(f"Error: Cannot open file {file1}", file=sys.stderr)
        sys.exit(1)

    # Read second file and join with first
    try:
        with open(file2, 'r') as f:
            for line in f:
                contig, gstart = parse_line(line)
                if contig:
                    # Find matching ID in parray
                    for prow in parray:
                        if contig == prow[0]:
                            print(f"{prow[0]}\t{prow[1]}\t{gstart}")
    except FileNotFoundError:
        print(f"Error: Cannot open file {file2}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
