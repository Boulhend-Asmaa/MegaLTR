#!/usr/bin/env python3
"""
Python port of print.pl

Purpose: Reformats LTRdigest CSV output by reordering columns and adding a composite ID.

Original Perl script had a bug:
- Regex pattern ([\\S|\\s]+) is incorrect - the pipe | inside [] is literal, not OR
- Should be (\\S+) or (.+) or (.*) for "rest of line"

This Python version fixes the bug and handles tab-separated input correctly.

Usage: python3 print_ltrdigest.py <input_csv>
"""

import sys


def main():
    if len(sys.argv) != 2:
        print("Usage: print_ltrdigest.py <input_csv>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]

    try:
        with open(input_file, 'r') as f:
            for line in f:
                line = line.rstrip('\n')

                # Split on tab - the original CSV is actually tab-separated
                parts = line.split('\t')

                # Original Perl splits into 5 parts: id1, id2, id3, id4, id5 (rest)
                # But it uses a buggy regex that could miss data
                # We'll handle this robustly:
                if len(parts) >= 5:
                    id1 = parts[0]  # element
                    id2 = parts[1]  # id element start
                    id3 = parts[2]  # element end
                    id4 = parts[3]  # element length
                    id5 = '\t'.join(parts[4:])  # rest of the columns

                    # Original output format: $id4_$id1_$id2\t$id4\t$id1\t$id2\t$id3\t$id5
                    composite_id = f"{id4}_{id1}_{id2}"
                    print(f"{composite_id}\t{id4}\t{id1}\t{id2}\t{id3}\t{id5}")

    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
