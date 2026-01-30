# MegaLTR v2.0 Deployment Guide

**From**: Asmaa Boulhend
**To**: Development Team
**Subject**: Deploying New MegaLTR Nextflow Pipeline on University Server

---

Hi,

Here's everything you need to deploy the new MegaLTR v2.0 on our university server (webserver + HPC). This new version replaces the old Bash-based MegaLTR with a modern Nextflow pipeline.

---

## 1. What Changed?

| Component | Old Version | New Version |
|-----------|-------------|-------------|
| Pipeline | `MegaLTR.sh` (Bash script) | `main.nf` (Nextflow workflow) |
| Environment | `environment.yml` | `MegaLTR.clean.yml` |
| Execution | `bash MegaLTR.sh ...` | `nextflow run main.nf ...` |
| HPC Support | Manual job scripts | Built-in SLURM profile |

**Important**: The scientific output is identical - same LTR counts, same LAI scores, same classifications. Only the execution method changed.

---

## 2. Webserver Deployment

### 2.1 Get the Code

```bash
cd /var/www/  # or your web application directory
git clone https://github.com/Boulhend-Asmaa/MegaLTR.git
cd MegaLTR
git checkout feat/phase6_Nextflow  # or 'main' after merge
```

### 2.2 Install Nextflow

```bash
# Install Nextflow (one-time)
curl -s https://get.nextflow.io | bash
sudo mv nextflow /usr/local/bin/

# Verify installation
nextflow -version
```

### 2.3 Create Conda Environment

```bash
# Create the environment (takes ~20-30 minutes)
conda env create -f MegaLTR.clean.yml -n MegaLTR

# Verify it works
conda activate MegaLTR
which gt  # should show path to genometools
conda deactivate
```

### 2.4 Update Web Application Backend

Replace old MegaLTR calls with new Nextflow commands:

**OLD Command (Bash):**
```bash
bash MegaLTR.sh -i genome.fna -g annotation.gff -o output_dir -t 3 -T 8
```

**NEW Command (Nextflow):**
```bash
nextflow run /var/www/MegaLTR/main.nf \
  --genome /path/to/genome.fna \
  --gff /path/to/annotation.gff \
  --outdir /path/to/output_dir \
  --analysis_type 3 \
  --threads 8 \
  -profile conda
```

### 2.5 Parameter Mapping Table

| Old Parameter | New Parameter | Description |
|---------------|---------------|-------------|
| `-i <file>` | `--genome <file>` | Input genome FASTA |
| `-g <file>` | `--gff <file>` | Gene annotation GFF |
| `-o <dir>` | `--outdir <dir>` | Output directory |
| `-t <1-4>` | `--analysis_type <1-4>` | Analysis type |
| `-p <name>` | `--prefix <name>` | Output file prefix |
| `-T <num>` | `--threads <num>` | Number of CPU threads |

### 2.6 Analysis Types (unchanged)

| Type | Description |
|------|-------------|
| 1 | LTR-RT identification + domain annotation |
| 2 | Type 1 + insertion time calculation |
| 3 | Type 2 + gene-chimera analysis + visualization |
| 4 | LAI calculation only |

### 2.7 Backend Code Examples

**Python/Django:**
```python
import subprocess
import os

def run_megaltr(genome_path, gff_path, output_dir, analysis_type=3, threads=8):
    """Run MegaLTR Nextflow pipeline"""

    cmd = [
        'nextflow', 'run', '/var/www/MegaLTR/main.nf',
        '--genome', genome_path,
        '--gff', gff_path,
        '--outdir', output_dir,
        '--analysis_type', str(analysis_type),
        '--threads', str(threads),
        '-profile', 'conda'
    ]

    # Run in background
    process = subprocess.Popen(
        cmd,
        stdout=open(os.path.join(output_dir, 'nextflow.log'), 'w'),
        stderr=subprocess.STDOUT,
        cwd='/var/www/MegaLTR'
    )

    return process.pid  # Return PID for tracking
```

**PHP:**
```php
function run_megaltr($genome_path, $gff_path, $output_dir, $analysis_type = 3, $threads = 8) {
    $megaltr_dir = '/var/www/MegaLTR';

    $cmd = "cd $megaltr_dir && nextflow run main.nf " .
           "--genome '$genome_path' " .
           "--gff '$gff_path' " .
           "--outdir '$output_dir' " .
           "--analysis_type $analysis_type " .
           "--threads $threads " .
           "-profile conda " .
           "> '$output_dir/nextflow.log' 2>&1 &";

    exec($cmd, $output, $return_code);
    return $return_code === 0;
}
```

**Node.js:**
```javascript
const { spawn } = require('child_process');
const path = require('path');

function runMegaLTR(genomePath, gffPath, outputDir, analysisType = 3, threads = 8) {
    const megaltrDir = '/var/www/MegaLTR';

    const process = spawn('nextflow', [
        'run', 'main.nf',
        '--genome', genomePath,
        '--gff', gffPath,
        '--outdir', outputDir,
        '--analysis_type', String(analysisType),
        '--threads', String(threads),
        '-profile', 'conda'
    ], {
        cwd: megaltrDir,
        detached: true,
        stdio: ['ignore', 'pipe', 'pipe']
    });

    return process.pid;
}
```

---

## 3. HPC Deployment (SLURM)

### 3.1 Initial Setup

```bash
# Clone repository
git clone https://github.com/Boulhend-Asmaa/MegaLTR.git
cd MegaLTR
git checkout feat/phase6_Nextflow

# Install Nextflow for user
curl -s https://get.nextflow.io | bash
mv nextflow ~/.local/bin/

# Load modules
module load Anaconda3
module load Java/17

# Create local conda environment
conda env create -f MegaLTR.clean.yml -p ./conda_env
```

### 3.2 Running on HPC

```bash
# Basic execution
nextflow run main.nf -profile hpc \
  --genome /path/to/genome.fna \
  --gff /path/to/annotation.gff \
  --analysis_type 3

# Resume after timeout or failure
nextflow run main.nf -profile hpc -resume \
  --genome /path/to/genome.fna \
  --gff /path/to/annotation.gff \
  --analysis_type 3
```

### 3.3 HPC Profile Settings

The HPC profile is pre-configured in `nextflow.config`:

```groovy
hpc {
    params.threads = 32
    params.max_cpus = 56
    params.max_memory = '180.GB'
    params.max_time = '36.h'  // UM6P QOS limit

    process.executor = 'slurm'
    process.queue = 'compute'
    process.clusterOptions = '--qos=default-cpu'
    process.beforeScript = 'module load Anaconda3'
}
```

**To customize for different HPC clusters**, edit these values in `nextflow.config`.

---

## 4. Output Files Location

Results are saved in the `--outdir` directory (default: `megaltr_results/`):

```
megaltr_results/
├── ltr_retriever/
│   ├── results.fna.pass.list          # Intact LTR-RT list
│   ├── results.fna.pass.list.gff3     # GFF3 annotations
│   └── results.fna.out.LAI            # LAI score
├── results/
│   ├── Final_annotation_file.tsv      # Complete annotation table
│   ├── LTR_RT.fa                      # Extracted sequences
│   ├── LTR_RT_NonRedondant.fa         # Non-redundant library
│   └── results.statistics.tsv         # Summary statistics
├── insertion_time/
│   ├── InsertionTime_histogram.pdf    # Age distribution plot
│   └── InsertionTime_boxplot.pdf      # Age by superfamily
├── gene_analysis/
│   ├── LTR_gene_chimeras.tsv          # Gene-chimera LTRs
│   └── genes_up_and_down_LTR.tsv      # Nearby genes
└── visualization/
    └── chromosome_density.pdf          # Density plot
```

---

## 5. Checking Job Status

### On Webserver
```bash
# Check if Nextflow is running
ps aux | grep nextflow

# Check log file
tail -f /path/to/output_dir/nextflow.log
```

### On HPC
```bash
# Check SLURM queue
squeue -u $USER

# Check Nextflow log
tail -f .nextflow.log
```

---

## 6. Troubleshooting

| Error | Solution |
|-------|----------|
| `nextflow: command not found` | Add Nextflow to PATH: `export PATH=$PATH:~/.local/bin` |
| `conda: command not found` | Load Anaconda module: `module load Anaconda3` |
| `Java not found` | Install Java 11+ or load module: `module load Java/17` |
| `Job timeout on HPC` | Use `-resume` flag to continue from checkpoint |
| `Out of memory` | Pipeline auto-retries with more memory; or increase in config |

---

## 7. Quick Comparison: Old vs New

### Testing a Small Genome (Ananas, 382MB)

**Old:**
```bash
conda activate MegaLTR
bash MegaLTR.sh -i Ananas.fna -g Ananas.gff -o output -t 3
# Runtime: ~6 hours
```

**New:**
```bash
nextflow run main.nf --genome Ananas.fna --gff Ananas.gff --analysis_type 3 -profile conda
# Runtime: ~4 hours (webserver) or ~1 hour (HPC)
```

**Results: Identical** (594 LTR-RTs, LAI = 8.7)

---

## 8. Files to Deploy

| File | Required | Description |
|------|----------|-------------|
| `main.nf` | Yes | Nextflow workflow |
| `nextflow.config` | Yes | Configuration |
| `MegaLTR.clean.yml` | Yes | Conda environment |
| `bin/` | Yes | All scripts (Python, Perl) |
| `README.md` | Recommended | Documentation |

---

## 9. Contact

If you have questions during deployment:
- **Asmaa Boulhend** - Pipeline development
- **Repository**: https://github.com/Boulhend-Asmaa/MegaLTR
- **Branch**: `feat/phase6_Nextflow` (or `main` after merge)

---

Let me know if you need any clarification or run into issues during deployment!

Best regards,
Asmaa Boulhend
