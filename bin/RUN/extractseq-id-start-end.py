#!/usr/bin/env python3
import sys
import gzip
from typing import Dict, List, Tuple

def open_maybe_gz(path: str):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, "rt", encoding="utf-8", errors="replace")

def read_coords(ids_file: str) -> Dict[str, List[Tuple[int,int,str,str,str,str]]]:
    """
    Perl expects 7 tokens per line:
      key st et pm sm sm1 sm2   (sm3 is buggy/unused in Perl)
    It stores 6 values and uses pm, sm2, sm, sm1 in the header.
    """
    coords: Dict[str, List[Tuple[int,int,str,str,str,str]]] = {}
    with open_maybe_gz(ids_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 7:
                continue
            key = parts[0]
            st  = int(float(parts[1]))
            et  = int(float(parts[2]))
            pm  = parts[3]
            sm  = parts[4]
            sm1 = parts[5]
            sm2 = parts[6]
            coords.setdefault(key, []).append((st, et, pm, sm, sm1, sm2))
    return coords

def fasta_iter(path: str):
    """
    Simple FASTA iterator (supports .gz).
    Yields (header_id, sequence_string).
    """
    with open_maybe_gz(path) as f:
        sid = None
        seq_chunks = []
        for line in f:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if sid is not None:
                    yield sid, "".join(seq_chunks)
                sid = line[1:].split()[0]
                seq_chunks = []
            else:
                if sid is not None and line:
                    seq_chunks.append(line.strip())
        if sid is not None:
            yield sid, "".join(seq_chunks)

def main():
    if len(sys.argv) < 4:
        print("Usage: extractseq-id-start-end.py <fasta> <ids_file> <result_fasta>", file=sys.stderr)
        return 2

    fasta_path = sys.argv[1]
    ids_file   = sys.argv[2]
    out_path   = sys.argv[3]

    coords = read_coords(ids_file)
    if not coords:
        # No coordinates -> write nothing, but not a hard failure
        return 0

    # Append like the Perl script (>>)
    out = open(out_path, "a", encoding="utf-8")

    # Stream through FASTA and extract only needed IDs
    found_any = False
    for sid, seq in fasta_iter(fasta_path):
        if sid not in coords:
            continue
        found_any = True
        for (st, et, pm, sm, sm1, sm2) in coords[sid]:
            # Perl substr is 0-based; keep the same behavior
            if st < 0:
                st = 0
            if et < st:
                continue
            subseq = seq[st:et]
            header = f"{sid}..{st}..{et}-{pm}-{sm2}#{sm}/{sm1}"
            out.write(f">{header}\n")
            # wrap sequence (60 chars/line)
            for i in range(0, len(subseq), 60):
                out.write(subseq[i:i+60] + "\n")

    out.close()
    return 0 if found_any else 0

if __name__ == "__main__":
    sys.exit(main())
