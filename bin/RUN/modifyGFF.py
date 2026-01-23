import sys
import shutil

if len(sys.argv) != 4:
    print("Usage: python script.py input_file mapping_file order")
    sys.exit(1)

input_file = sys.argv[1]
mapping_file = sys.argv[2]
order = sys.argv[3]

mappings = {}

with open(mapping_file, 'r') as file:
    for line in file:
        word, replacement = line.strip().split('=')

        if order == '2':
            mappings[replacement.replace('>','')] = word.replace('>','')
        elif order == '1':
            mappings[word.replace('>','')] = replacement.replace('>','')
        else:
            print("order must be 1 or 2")
            sys.exit(1)

print(f"[modifyGFF.py] Loaded {len(mappings)} ID mappings")

temp_output_file = input_file + ".tmp"

processed = 0
with open(input_file, 'r') as infile, open(temp_output_file, 'w') as outfile:
    for line in infile:
        if not line.startswith('#'):
            # Use str.replace() instead of re.sub() - much faster for literal strings
            # Also check if replacement exists in line before replacing (avoids unnecessary work)
            for replacement, word in mappings.items():
                if replacement in line:
                    line = line.replace(replacement, word)
        outfile.write(line)
        processed += 1
        if processed % 10000 == 0:
            print(f"[modifyGFF.py] Processed {processed} lines...")

shutil.move(temp_output_file, input_file)

print(f"[modifyGFF.py] Complete: {processed} lines processed")
