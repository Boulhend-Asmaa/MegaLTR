#!/usr/bin/env python3
import sys
import gzip

def open_maybe_gz(path: str):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, "rt", encoding="utf-8", errors="replace")

def main():
    if len(sys.argv) < 2:
        print("Usage: checkfasta.py <fasta(.gz)>", file=sys.stderr)
        return 2

    fasta = sys.argv[1]
    n_headers = 0
    n_seq_lines = 0

    try:
        with open_maybe_gz(fasta) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                if line.startswith(">"):
                    n_headers += 1
                else:
                    n_seq_lines += 1
    except FileNotFoundError:
        print(f"ERROR: FASTA file not found: {fasta}", file=sys.stderr)
        return 2
    except Exception as e:
        print(f"ERROR: Cannot read FASTA: {e}", file=sys.stderr)
        return 2

    if n_headers == 0:
        print("ERROR: No FASTA headers found. File is not valid FASTA.", file=sys.stderr)
        return 2

    # Minimal validation OK
    print(f"FASTA OK: sequences={n_headers}, sequence_lines={n_seq_lines}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
