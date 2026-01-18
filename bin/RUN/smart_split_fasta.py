#!/usr/bin/env python3
"""
Intelligent FASTA splitting for parallel LTR detection.

Splits genome FASTA into adaptive chunks based on sequence count,
never splitting within a sequence. Supports both plain and gzipped FASTA.

Author: Asmaa Boulhend
Date: 2026-01-12
Project: MegaLTR Pipeline Optimization - Phase 5

Usage:
    python3 smart_split_fasta.py <input.fna> <output_dir> [options]

Options:
    --threads N         Number of threads (default: 4)
    --max-chunks N      Maximum chunks (default: threads * 4)
    --min-seqs-chunk N  Minimum sequences per chunk (default: 1)
    --prefix NAME       Output file prefix (default: chunk)
    --validate          Only validate and report statistics (no splitting)
    --verbose, -v       Verbose output

Examples:
    # Auto mode (recommended)
    python3 smart_split_fasta.py genome.fna ./chunks --threads 4

    # Validation only
    python3 smart_split_fasta.py genome.fna ./chunks --validate --verbose

    # Custom chunk count
    python3 smart_split_fasta.py genome.fna ./chunks --max-chunks 8

Features:
    - FASTA-record aware (never splits within sequence)
    - Supports .fna and .fna.gz (auto-detection)
    - Adaptive chunk count based on sequence count
    - Balanced chunk sizes (bin-packing algorithm)
    - Zero empty chunks guaranteed
    - Preserves headers exactly as-is
    - Comprehensive validation mode
"""

import sys
import os
import gzip
import argparse
from pathlib import Path
from typing import List, Tuple, Dict
from collections import namedtuple

# Sequence record structure
SeqRecord = namedtuple('SeqRecord', ['header', 'sequence', 'length'])


def is_gzipped(file_path: str) -> bool:
    """
    Check if file is gzip compressed by reading magic bytes.

    Args:
        file_path: Path to file

    Returns:
        bool: True if gzipped, False otherwise
    """
    try:
        with open(file_path, 'rb') as f:
            return f.read(2) == b'\x1f\x8b'
    except Exception:
        return False


def open_fasta(file_path: str):
    """
    Open FASTA file, automatically handling gzip compression.

    Args:
        file_path: Path to FASTA file (.fna or .fna.gz)

    Returns:
        File handle (text mode)
    """
    if is_gzipped(file_path):
        return gzip.open(file_path, 'rt')
    else:
        return open(file_path, 'r')


def parse_fasta_records(file_path: str) -> List[SeqRecord]:
    """
    Parse FASTA file into sequence records.

    Args:
        file_path: Path to FASTA file

    Returns:
        List of SeqRecord objects (header, sequence, length)
    """
    records = []
    current_header = None
    current_seq = []

    with open_fasta(file_path) as f:
        for line in f:
            line = line.rstrip('\n\r')

            if line.startswith('>'):
                # Save previous record
                if current_header is not None:
                    seq_str = ''.join(current_seq)
                    records.append(SeqRecord(
                        header=current_header,
                        sequence=seq_str,
                        length=len(seq_str)
                    ))

                # Start new record
                current_header = line
                current_seq = []
            else:
                # Accumulate sequence
                current_seq.append(line)

        # Save last record
        if current_header is not None:
            seq_str = ''.join(current_seq)
            records.append(SeqRecord(
                header=current_header,
                sequence=seq_str,
                length=len(seq_str)
            ))

    return records


def calculate_statistics(records: List[SeqRecord]) -> Dict:
    """
    Calculate statistics for FASTA records.

    Args:
        records: List of SeqRecord objects

    Returns:
        Dictionary with statistics
    """
    if not records:
        return {
            'num_sequences': 0,
            'total_bases': 0,
            'min_length': 0,
            'max_length': 0,
            'mean_length': 0,
            'median_length': 0
        }

    lengths = [r.length for r in records]
    lengths_sorted = sorted(lengths)

    stats = {
        'num_sequences': len(records),
        'total_bases': sum(lengths),
        'min_length': min(lengths),
        'max_length': max(lengths),
        'mean_length': sum(lengths) // len(lengths),
        'median_length': lengths_sorted[len(lengths_sorted) // 2]
    }

    return stats


def determine_chunk_count(num_sequences: int, nthreads: int, max_chunks: int = None) -> int:
    """
    Determine optimal number of chunks based on sequence count.

    Strategy:
    - Default: min(num_sequences, threads * 4)
    - Rationale: 4 chunks per thread provides good task granularity
    - Never exceed num_sequences (no empty chunks)

    Args:
        num_sequences: Total number of sequences in FASTA
        nthreads: Number of worker threads
        max_chunks: Maximum chunks allowed (default: threads * 4)

    Returns:
        int: Optimal chunk count (1 to num_sequences)
    """
    if num_sequences == 0:
        return 0

    if max_chunks is None:
        max_chunks = nthreads * 4

    # Never create more chunks than sequences
    optimal = min(num_sequences, max_chunks)

    return max(1, optimal)


def split_records_balanced(records: List[SeqRecord], num_chunks: int) -> List[List[SeqRecord]]:
    """
    Split records into balanced chunks using greedy bin-packing.

    Algorithm:
    1. Sort sequences by length (largest first)
    2. For each sequence, assign to chunk with smallest current size
    3. Result: well-balanced chunks, no empty chunks

    Args:
        records: List of SeqRecord objects
        num_chunks: Number of chunks to create

    Returns:
        List of chunks, each chunk is a list of SeqRecord objects
    """
    if not records:
        return []

    if num_chunks > len(records):
        num_chunks = len(records)

    # Sort sequences by length (largest first) for better bin-packing
    sorted_records = sorted(records, key=lambda r: r.length, reverse=True)

    # Initialize chunks
    chunks = [[] for _ in range(num_chunks)]
    chunk_sizes = [0] * num_chunks

    # Greedy assignment: assign each sequence to smallest chunk
    for record in sorted_records:
        # Find chunk with minimum current size
        min_idx = chunk_sizes.index(min(chunk_sizes))
        chunks[min_idx].append(record)
        chunk_sizes[min_idx] += record.length

    # Filter out empty chunks (should not happen with correct logic)
    chunks = [chunk for chunk in chunks if chunk]

    return chunks


def write_chunk(chunk: List[SeqRecord], output_path: str) -> Dict:
    """
    Write chunk to FASTA file.

    Args:
        chunk: List of SeqRecord objects
        output_path: Path to output FASTA file

    Returns:
        Dictionary with chunk statistics
    """
    num_sequences = len(chunk)
    total_bases = sum(r.length for r in chunk)

    with open(output_path, 'w') as f:
        for record in chunk:
            f.write(f"{record.header}\n")
            # Write sequence in 80-character lines (FASTA standard)
            seq = record.sequence
            for i in range(0, len(seq), 80):
                f.write(f"{seq[i:i+80]}\n")

    return {
        'path': output_path,
        'num_sequences': num_sequences,
        'total_bases': total_bases
    }


def split_fasta(input_file: str, output_dir: str, num_chunks: int, prefix: str = "chunk") -> List[Dict]:
    """
    Split FASTA file into balanced chunks.

    Args:
        input_file: Path to input FASTA file
        output_dir: Directory for output chunks
        num_chunks: Number of chunks to create
        prefix: Prefix for chunk filenames

    Returns:
        List of dictionaries with chunk information
    """
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Parse FASTA records
    print(f"Parsing FASTA file: {input_file}", file=sys.stderr)
    records = parse_fasta_records(input_file)

    if not records:
        print(f"Warning: No sequences found in {input_file}", file=sys.stderr)
        return []

    # Split into balanced chunks
    print(f"Splitting into {num_chunks} chunks...", file=sys.stderr)
    chunks = split_records_balanced(records, num_chunks)

    # Write chunks
    chunk_info = []
    for i, chunk in enumerate(chunks):
        chunk_path = output_dir / f"{prefix}_{i+1:03d}.fna"
        info = write_chunk(chunk, str(chunk_path))
        chunk_info.append(info)

    return chunk_info


def print_validation_report(input_file: str, records: List[SeqRecord], chunk_info: List[Dict] = None):
    """
    Print comprehensive validation report.

    Args:
        input_file: Path to input FASTA file
        records: List of SeqRecord objects
        chunk_info: Optional list of chunk information dictionaries
    """
    stats = calculate_statistics(records)

    print("\n" + "=" * 60)
    print("FASTA Validation Report")
    print("=" * 60)

    print(f"\nInput File: {input_file}")
    print(f"File size: {os.path.getsize(input_file) / 1024 / 1024:.2f} MB")
    print(f"Compressed: {'Yes (gzip)' if is_gzipped(input_file) else 'No'}")

    print(f"\nSequence Statistics:")
    print(f"  Total sequences: {stats['num_sequences']}")
    print(f"  Total bases: {stats['total_bases']:,} bp ({stats['total_bases'] / 1e6:.2f} Mb)")
    print(f"  Min length: {stats['min_length']:,} bp")
    print(f"  Max length: {stats['max_length']:,} bp")
    print(f"  Mean length: {stats['mean_length']:,} bp")
    print(f"  Median length: {stats['median_length']:,} bp")

    if stats['num_sequences'] <= 20:
        print(f"\nSequence Details:")
        for i, record in enumerate(records, 1):
            header_short = record.header[:60] + "..." if len(record.header) > 60 else record.header
            print(f"  {i}. {header_short}")
            print(f"     Length: {record.length:,} bp")

    if chunk_info:
        print(f"\nChunk Distribution:")
        print(f"  Number of chunks: {len(chunk_info)}")

        chunk_bases = [info['total_bases'] for info in chunk_info]
        chunk_seqs = [info['num_sequences'] for info in chunk_info]

        print(f"  Sequences per chunk: {min(chunk_seqs)}-{max(chunk_seqs)} (avg: {sum(chunk_seqs) / len(chunk_seqs):.1f})")
        print(f"  Bases per chunk: {min(chunk_bases):,}-{max(chunk_bases):,} bp (avg: {sum(chunk_bases) / len(chunk_bases):,.0f} bp)")

        # Balance metric (coefficient of variation)
        mean_bases = sum(chunk_bases) / len(chunk_bases)
        variance = sum((x - mean_bases) ** 2 for x in chunk_bases) / len(chunk_bases)
        cv = (variance ** 0.5) / mean_bases if mean_bases > 0 else 0

        print(f"  Balance (CV): {cv:.3f} (lower is better, < 0.2 is well-balanced)")

        print(f"\nChunk Details:")
        for i, info in enumerate(chunk_info, 1):
            print(f"  Chunk {i}: {info['num_sequences']} seqs, {info['total_bases']:,} bp")
            print(f"    File: {Path(info['path']).name}")

    print("=" * 60 + "\n")


def validate_chunks(chunk_files: List[str], original_records: List[SeqRecord]) -> bool:
    """
    Validate that chunks contain all original sequences.

    Args:
        chunk_files: List of chunk file paths
        original_records: Original FASTA records

    Returns:
        bool: True if validation passes, False otherwise
    """
    print("\nValidating chunks...", file=sys.stderr)

    # Parse all chunks
    chunk_records = []
    for chunk_file in chunk_files:
        chunk_records.extend(parse_fasta_records(chunk_file))

    # Compare counts
    original_count = len(original_records)
    chunk_count = len(chunk_records)

    if original_count != chunk_count:
        print(f"ERROR: Sequence count mismatch!", file=sys.stderr)
        print(f"  Original: {original_count} sequences", file=sys.stderr)
        print(f"  Chunks: {chunk_count} sequences", file=sys.stderr)
        return False

    # Compare total bases
    original_bases = sum(r.length for r in original_records)
    chunk_bases = sum(r.length for r in chunk_records)

    if original_bases != chunk_bases:
        print(f"ERROR: Base count mismatch!", file=sys.stderr)
        print(f"  Original: {original_bases} bp", file=sys.stderr)
        print(f"  Chunks: {chunk_bases} bp", file=sys.stderr)
        return False

    # Compare headers (verify no duplicates or missing sequences)
    original_headers = set(r.header for r in original_records)
    chunk_headers = set(r.header for r in chunk_records)

    if original_headers != chunk_headers:
        missing = original_headers - chunk_headers
        extra = chunk_headers - original_headers

        if missing:
            print(f"ERROR: Missing sequences in chunks: {len(missing)}", file=sys.stderr)
        if extra:
            print(f"ERROR: Extra sequences in chunks: {len(extra)}", file=sys.stderr)
        return False

    print("✓ Validation passed: All sequences preserved", file=sys.stderr)
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Smart FASTA splitting with adaptive chunk count (FASTA-record aware)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )

    parser.add_argument("input_file", help="Input FASTA file (.fna or .fna.gz)")
    parser.add_argument("output_dir", help="Output directory for chunk files")
    parser.add_argument("--threads", "-t", type=int, default=4,
                        help="Number of threads (default: 4)")
    parser.add_argument("--max-chunks", type=int, default=None,
                        help="Maximum number of chunks (default: threads * 4)")
    parser.add_argument("--min-seqs-chunk", type=int, default=1,
                        help="Minimum sequences per chunk (default: 1)")
    parser.add_argument("--prefix", default="chunk",
                        help="Output file prefix (default: chunk)")
    parser.add_argument("--validate", action="store_true",
                        help="Only validate and report statistics (no splitting)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Verbose output with detailed statistics")

    args = parser.parse_args()

    # Validate input file
    if not os.path.exists(args.input_file):
        print(f"Error: Input file not found: {args.input_file}", file=sys.stderr)
        sys.exit(1)

    # Parse FASTA
    records = parse_fasta_records(args.input_file)

    if not records:
        print(f"Error: No sequences found in {args.input_file}", file=sys.stderr)
        sys.exit(1)

    # Validation mode
    if args.validate:
        print_validation_report(args.input_file, records)
        sys.exit(0)

    # Determine chunk count
    num_sequences = len(records)
    num_chunks = determine_chunk_count(num_sequences, args.threads, args.max_chunks)

    if args.verbose:
        print(f"\nInput: {num_sequences} sequences")
        print(f"Threads: {args.threads}")
        print(f"Target chunks: {num_chunks}")

    # Split FASTA
    chunk_info = split_fasta(args.input_file, args.output_dir, num_chunks, args.prefix)

    if not chunk_info:
        print("Error: No chunks created", file=sys.stderr)
        sys.exit(1)

    # Verify no empty chunks
    empty_chunks = [info for info in chunk_info if info['num_sequences'] == 0]
    if empty_chunks:
        print(f"ERROR: {len(empty_chunks)} empty chunks created!", file=sys.stderr)
        sys.exit(1)

    # Validate chunks
    chunk_files = [info['path'] for info in chunk_info]
    if not validate_chunks(chunk_files, records):
        print("ERROR: Chunk validation failed!", file=sys.stderr)
        sys.exit(1)

    # Report results
    if args.verbose:
        print_validation_report(args.input_file, records, chunk_info)
    else:
        print(f"✓ Created {len(chunk_info)} chunks in {args.output_dir}")
        print(f"  Total sequences: {num_sequences}")
        print(f"  Sequences per chunk: {min(info['num_sequences'] for info in chunk_info)}-{max(info['num_sequences'] for info in chunk_info)}")

    sys.exit(0)


if __name__ == "__main__":
    main()
