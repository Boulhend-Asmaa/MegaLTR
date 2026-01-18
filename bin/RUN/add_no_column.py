#!/usr/bin/env python3
"""
Python port of No.pl

Purpose: Appends "No" column to each line of input file.
This marks LTR-RTs that are located outside gene start and end positions.

Original Perl script had 3 bugs:
1. Regex pattern ([\\S|\\s]+) is incorrect - the pipe | inside [] is literal, not OR
2. Closes wrong file handle (GFILE instead of PFILE) on line 14
3. Takes 2 arguments but only uses 1 ($processid is unused)

This Python version fixes all bugs and handles input correctly.

Usage: python3 add_no_column.py <input_file>
"""

import sys


def main():
    if len(sys.argv) != 2:
        print("Usage: add_no_column.py <input_file>", file=sys.stderr)
        sys.exit(1)

    input_file = sys.argv[1]

    try:
        with open(input_file, 'r') as f:
            for line in f:
                # Remove trailing newline/whitespace
                line = line.rstrip('\n\r')

                # Skip empty lines
                if not line:
                    continue

                # Append "\tNo" to each line
                # The original Perl checks if line matches ([\S|\s]+) which matches any line
                # So we just append "No" to every non-empty line
                print(f"{line}\tNo")

    except FileNotFoundError:
        print(f"Error: File '{input_file}' not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
