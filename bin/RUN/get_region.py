import sys

fasta_path = sys.argv[1]
name = sys.argv[2]
output = sys.argv[3]

# Parse LTR table to get coordinates
data = []
with open(name, 'r') as f:
    for line in f:
        parts = line.split()
        if len(parts) >= 10:  # Ensure we have enough columns
            # (ltr_name, chr, ltr5_start, ltr5_end, ltr3_start, ltr3_end)
            data.append((parts[0], parts[1], parts[5], parts[6], parts[8], parts[9]))

print(f"[get_region.py] Processing {len(data)} LTR elements from {fasta_path}")

# Parse FASTA file efficiently using list append (O(n) instead of O(n²))
sequences = {}
current_id = None
seq_parts = []

with open(fasta_path, 'r') as file:
    for line in file:
        line = line.rstrip('\n')
        if not line:
            continue
        if line[0] == '>':
            # Save previous sequence if exists
            if current_id is not None:
                sequences[current_id] = ''.join(seq_parts)
            # Start new sequence
            current_id = line.split()[0][1:]  # Remove '>' and take first word
            seq_parts = []
        else:
            seq_parts.append(line)

    # Don't forget the last sequence
    if current_id is not None:
        sequences[current_id] = ''.join(seq_parts)

print(f"[get_region.py] Loaded {len(sequences)} chromosomes/scaffolds")

# Extract LTR regions and write to files
processed = 0
skipped = 0

for ltr in data:
    ltr_name, chrom, ltr5_start, ltr5_end, ltr3_start, ltr3_end = ltr

    # Validate coordinates are numeric
    if not (ltr5_start.isnumeric() and ltr5_end.isnumeric() and
            ltr3_start.isnumeric() and ltr3_end.isnumeric()):
        skipped += 1
        continue

    # Check chromosome exists
    if chrom not in sequences:
        skipped += 1
        continue

    # Extract and write sequences
    with open(f"{output}/{ltr_name}.fasta", 'w') as outfile:
        seq = sequences[chrom]
        outfile.write(">5'\n")
        outfile.write(seq[int(ltr5_start):int(ltr5_end)] + "\n")
        outfile.write(">3'\n")
        outfile.write(seq[int(ltr3_start):int(ltr3_end)] + "\n")

    processed += 1

    # Progress indicator every 100 elements
    if processed % 100 == 0:
        print(f"[get_region.py] Processed {processed}/{len(data)} LTR elements...")

print(f"[get_region.py] Complete: {processed} processed, {skipped} skipped")
           
