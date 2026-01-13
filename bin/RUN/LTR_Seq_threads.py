#!/usr/bin/env python3
import sys
import os
import glob
from multiprocessing import Pool

# Args:
# 1 FASTAfile
# 2 LTRfiles (folder containing split files)
# 3 outdir
# 4 nprocess
# 5 extractseq (script path: .pl or .py)
FASTAfile = sys.argv[1]
LTRfiles  = sys.argv[2]
outdir    = sys.argv[3]
nprocess  = int(sys.argv[4])
extractseq = sys.argv[5]

# Avoid over-threading in BLAS libs
os.environ["OMP_NUM_THREADS"] = "1"
os.environ["OPENBLAS_NUM_THREADS"] = "1"
os.environ["MKL_NUM_THREADS"] = "1"
os.environ["VECLIB_MAXIMUM_THREADS"] = "1"
os.environ["NUMEXPR_NUM_THREADS"] = "1"

# Support both new (chunk*) and old (x*) chunk naming for backward compatibility
data = sorted(glob.glob(f"{LTRfiles}/chunk*"))
if not data:
    # Fallback to old split naming
    data = sorted(glob.glob(f"{LTRfiles}/x*"))
if not data:
    raise FileNotFoundError(
        f"No chunk files found in {LTRfiles} "
        f"(tried patterns: chunk*, x*)"
    )

out_fa = f"{outdir}/LTR-RT_Sequence.fa"

def run_one(fname: str) -> int:
    # Choose runner based on script extension
    if extractseq.endswith(".py"):
        cmd = f"python3 {extractseq} {FASTAfile} {fname} {out_fa}"
    else:
        cmd = f"perl {extractseq} {FASTAfile} {fname} {out_fa}"

    ret = os.system(cmd)
    if ret != 0:
        raise SystemExit(f"ERROR: extractseq failed (exit={ret}): {cmd}")
    return ret

if __name__ == "__main__":
    # Ensure output file starts clean
    # (MegaLTR expects appending to this file)
    if os.path.exists(out_fa):
        os.remove(out_fa)

    with Pool(nprocess) as p:
        p.map(run_one, data)

