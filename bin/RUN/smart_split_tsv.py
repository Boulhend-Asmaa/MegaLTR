#!/usr/bin/env python3
"""
Intelligent TSV file splitting with adaptive chunk count and zero empty files.

This script replaces the inefficient 'split -n l/100' command that creates
61% empty files for small inputs (e.g., 39 LTRs → 100 chunks → 61 empty).

Author: Asmaa Boulhend
Date: 2026-01-12
Project: MegaLTR Pipeline Optimization

Usage:
    python3 smart_split_tsv.py <input_file> <output_dir> [options]

Options:
    --threads N       Number of threads (default: 4)
    --max-chunks N    Maximum chunks (default: auto)
    --chunk-size N    Target lines per chunk (default: auto)
    --prefix NAME     Output file prefix (default: chunk)
    --verbose, -v     Verbose output with statistics

Example:
    python3 smart_split_tsv.py coords.tsv ./chunks --threads 4 --verbose

    Input: 39 lines
    Output: 16 chunks (2-3 lines each), 0 empty files
    Old method: 100 chunks, 61 empty files
"""

import sys
import os
import argparse
from pathlib import Path


def count_lines(file_path):
    """
    Count non-empty lines in file.

    Args:
        file_path: Path to input file

    Returns:
        int: Number of non-empty lines
    """
    try:
        with open(file_path) as f:
            return sum(1 for line in f if line.strip())
    except FileNotFoundError:
        print(f"Error: File not found: {file_path}", file=sys.stderr)
        sys.exit(1)
    except PermissionError:
        print(f"Error: Permission denied: {file_path}", file=sys.stderr)
        sys.exit(1)


def determine_chunk_count(total_lines, nthreads, max_chunks=None):
    """
    Determine optimal number of chunks based on input size.

    Strategy:
    - Small inputs (< 100 lines): min(lines, nthreads * 4)
      Rationale: 4 batches per thread provides good task granularity
    - Large inputs (>= 100 lines): min(max_chunks, lines // 10)
      Rationale: ~10 lines per chunk balances parallelism and overhead
    - Never exceed total_lines (guarantees no empty chunks)

    Args:
        total_lines: Total lines in input file
        nthreads: Number of worker threads
        max_chunks: Maximum chunks allowed (default: 100)

    Returns:
        int: Optimal chunk count (1 to total_lines)
    """
    if total_lines == 0:
        return 0

    if max_chunks is None:
        max_chunks = 100

    if total_lines < 100:
        # Small input: create enough chunks for parallelism but not too many
        optimal = min(total_lines, nthreads * 4)
    else:
        # Large input: aim for ~10 lines per chunk
        optimal = min(max_chunks, max(10, total_lines // 10))

    # Never create more chunks than lines
    return max(1, min(optimal, total_lines))


def split_file(input_file, output_dir, num_chunks, prefix="chunk"):
    """
    Split file into num_chunks parts with balanced line distribution.

    Algorithm:
    1. Calculate base lines per chunk: floor(total / chunks)
    2. Calculate remainder: total % chunks
    3. First 'remainder' chunks get (base + 1) lines
    4. Remaining chunks get base lines
    5. Result: perfectly balanced, no empty chunks

    Example:
        39 lines, 16 chunks:
        - Base: 39 // 16 = 2
        - Remainder: 39 % 16 = 7
        - Chunks 0-6: 3 lines each (7 chunks)
        - Chunks 7-15: 2 lines each (9 chunks)
        - Total: 7*3 + 9*2 = 21 + 18 = 39 ✓

    Args:
        input_file: Path to input TSV file
        output_dir: Directory for output chunks
        num_chunks: Number of chunks to create
        prefix: Prefix for chunk filenames

    Returns:
        list: Paths to created chunk files (no empty files)
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Read all non-empty lines
    with open(input_file) as f:
        lines = [line for line in f if line.strip()]

    total_lines = len(lines)
    if total_lines == 0:
        print(f"Warning: Input file is empty: {input_file}", file=sys.stderr)
        return []

    # Calculate balanced distribution
    base_lines = total_lines // num_chunks
    remainder = total_lines % num_chunks

    # Split and write chunks
    chunk_files = []
    line_idx = 0

    for i in range(num_chunks):
        # First 'remainder' chunks get one extra line
        chunk_size = base_lines + (1 if i < remainder else 0)

        if chunk_size == 0:
            # Safety check (should never happen with correct logic)
            break

        # Write chunk
        chunk_path = output_dir / f"{prefix}{i:04d}"
        with open(chunk_path, 'w') as out:
            for _ in range(chunk_size):
                if line_idx < total_lines:
                    out.write(lines[line_idx])
                    line_idx += 1

        chunk_files.append(str(chunk_path))

    # Verify all lines written
    if line_idx != total_lines:
        print(f"Warning: Expected {total_lines} lines, wrote {line_idx}", file=sys.stderr)

    return chunk_files


def print_statistics(input_file, chunk_files, total_lines, num_chunks_requested):
    """
    Print detailed splitting statistics.

    Args:
        input_file: Original input file path
        chunk_files: List of created chunk file paths
        total_lines: Total lines in input
        num_chunks_requested: Requested chunk count
    """
    print(f"\n=== Splitting Statistics ===")
    print(f"Input file: {input_file}")
    print(f"Total lines: {total_lines}")
    print(f"Chunks requested: {num_chunks_requested}")
    print(f"Chunks created: {len(chunk_files)}")

    if chunk_files:
        chunk_sizes = [count_lines(cf) for cf in chunk_files]
        min_size = min(chunk_sizes)
        max_size = max(chunk_sizes)
        avg_size = total_lines / len(chunk_files)

        print(f"Lines per chunk: {min_size}-{max_size} (avg: {avg_size:.1f})")
        print(f"Empty files: 0")

        # Compare to old method
        old_empty = max(0, 100 - total_lines)
        if old_empty > 0:
            improvement = (old_empty / 100) * 100
            print(f"\nComparison to 'split -n l/100':")
            print(f"  Old: 100 chunks, {old_empty} empty ({improvement:.0f}% waste)")
            print(f"  New: {len(chunk_files)} chunks, 0 empty (0% waste)")
            print(f"  Improvement: {100 - len(chunk_files)} fewer files ({(100 - len(chunk_files))/100*100:.0f}% reduction)")
    else:
        print("No chunks created (empty input)")

    print(f"Output directory: {Path(chunk_files[0]).parent if chunk_files else 'N/A'}")
    print("=" * 40)


def main():
    parser = argparse.ArgumentParser(
        description="Smart TSV splitting with adaptive chunk count (no empty files)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto mode (recommended)
  python3 smart_split_tsv.py input.tsv ./chunks --threads 4

  # Limit maximum chunks
  python3 smart_split_tsv.py input.tsv ./chunks --max-chunks 50

  # Target specific chunk size
  python3 smart_split_tsv.py input.tsv ./chunks --chunk-size 10

  # Verbose output with statistics
  python3 smart_split_tsv.py input.tsv ./chunks --verbose

Algorithm:
  - Small inputs (< 100 lines): Creates min(lines, threads * 4) chunks
  - Large inputs (≥ 100 lines): Creates min(max_chunks, lines / 10) chunks
  - Guarantees: No empty chunks, balanced distribution, all lines preserved

Comparison to 'split -n l/100':
  39 lines → Old: 100 chunks (61 empty), New: 16 chunks (0 empty)
  500 lines → Old: 100 chunks (0 empty), New: 50 chunks (0 empty)
        """
    )

    parser.add_argument("input_file", help="Input TSV file to split")
    parser.add_argument("output_dir", help="Output directory for chunk files")
    parser.add_argument("--threads", "-t", type=int, default=4,
                        help="Number of threads (default: 4)")
    parser.add_argument("--max-chunks", type=int, default=None,
                        help="Maximum number of chunks (default: auto)")
    parser.add_argument("--chunk-size", type=int, default=None,
                        help="Target lines per chunk (default: auto)")
    parser.add_argument("--prefix", default="chunk",
                        help="Output file prefix (default: chunk)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Verbose output with statistics")

    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.input_file):
        print(f"Error: Input file not found: {args.input_file}", file=sys.stderr)
        sys.exit(1)

    # Count lines
    total_lines = count_lines(args.input_file)

    if total_lines == 0:
        print(f"Warning: Input file is empty: {args.input_file}")
        print("No chunks created.")
        sys.exit(0)

    # Determine chunk count
    if args.chunk_size:
        # User-specified chunk size
        num_chunks = max(1, (total_lines + args.chunk_size - 1) // args.chunk_size)
    else:
        # Auto mode
        num_chunks = determine_chunk_count(total_lines, args.threads, args.max_chunks)

    # Split file
    chunk_files = split_file(args.input_file, args.output_dir, num_chunks, args.prefix)

    # Verify no empty files (should never happen with correct logic)
    empty_count = sum(1 for cf in chunk_files if count_lines(cf) == 0)
    if empty_count > 0:
        print(f"ERROR: {empty_count} empty chunks created! This should not happen.", file=sys.stderr)
        sys.exit(1)

    # Report results
    if args.verbose:
        print_statistics(args.input_file, chunk_files, total_lines, num_chunks)
    else:
        print(f"Created {len(chunk_files)} chunks in {args.output_dir} (0 empty files)")

    # Success
    sys.exit(0)


if __name__ == "__main__":
    main()
