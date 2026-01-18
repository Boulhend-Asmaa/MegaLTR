# Phase 6: Immediate Next Steps

## ✅ What's Already Done (Right Now)

1. ✅ Created Phase 6 branch: `feat/nextflow-migration`
2. ✅ Created `main.nf` - Basic Nextflow workflow with 3 processes
3. ✅ Created `nextflow.config` - Configuration file
4. ✅ Created quick start guide
5. ⏳ Installing Nextflow + Java (in progress)

---

## 🚀 What To Do Next (Within 1 Hour)

### Step 1: Wait for Nextflow Installation
```bash
# Check if installation is complete
conda list | grep nextflow
nextflow -version
```

### Step 2: Test Nextflow Installation
```bash
# Run Nextflow hello world
nextflow run hello

# If this works, Nextflow is ready!
```

### Step 3: Test MegaLTR Workflow (Dry Run)
```bash
# Test workflow syntax
nextflow run main.nf --help

# Should show the help message without errors
```

### Step 4: First Real Run (Arabidopsis Test)
```bash
# Run the minimal workflow
nextflow run main.nf \\
  --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \\
  --gff Data_for_test/Arabidopsis_thaliana.gff \\
  --threads 4

# This will likely fail (expected!) - we'll fix errors iteratively
```

---

## 🐛 Expected Issues & Quick Fixes

### Issue 1: "Python script not found"
**Fix**: Update paths in `main.nf` processes to point to correct script locations

### Issue 2: "Permission denied"
**Fix**: Make scripts executable:
```bash
chmod +x bin/RUN/*.py
chmod +x bin/LTR_FINDER_parallel/*
```

### Issue 3: "Module not found"
**Fix**: Activate conda environment first:
```bash
conda activate base  # or your MegaLTR environment
```

---

## 📝 Today's Goal (Realistic)

**Goal**: Get `PREPARE_GENOME` process working

**Success = This output**:
```
[PREPARE_GENOME] Submitted process > PREPARE_GENOME (1)
[PREPARE_GENOME] genome_prepared.fna created
[PREPARE_GENOME] mapping.txt created
```

Don't worry about LTR_FINDER and LTR_HARVEST today - focus on ONE process!

---

## 🔧 Debugging Strategy

When you hit an error:

1. **Read the error message carefully**
2. **Check the work directory**: `cd work/XX/XXXXX...` (Nextflow shows path)
3. **Look at `.command.sh`**: See what command failed
4. **Look at `.command.log`**: See the error output
5. **Fix in `main.nf`**: Update the process
6. **Re-run**: `nextflow run main.nf ...`

Nextflow caches successful steps, so you don't re-run everything!

---

## 📚 Minimal Nextflow Knowledge Needed

You only need to understand 3 concepts today:

### 1. Process (a task)
```nextflow
process TASK_NAME {
    input:
    path my_file

    output:
    path "output.txt"

    script:
    """
    # Your bash commands here
    cat ${my_file} > output.txt
    """
}
```

### 2. Channel (data flow)
```nextflow
genome_ch = Channel.fromPath("genome.fna")
```

### 3. Workflow (connecting processes)
```nextflow
workflow {
    TASK_NAME(genome_ch)
}
```

That's it! Learn more as you need it.

---

## 🎯 Phase 6 Milestones (Aggressive Timeline)

### Milestone 1: Working Process (Today/Tomorrow)
- [x] Install Nextflow
- [x] Create main.nf
- [ ] Get PREPARE_GENOME working
- [ ] Run without errors

### Milestone 2: Minimal Workflow (Days 2-3)
- [ ] Add LTR_FINDER process
- [ ] Add LTR_HARVEST process
- [ ] Connect processes with channels
- [ ] End-to-end execution (even if simplified)

### Milestone 3: Scientific Validation (Days 4-5)
- [ ] Compare outputs with Bash version
- [ ] Verify LTR counts match
- [ ] Check sequence extraction correctness

### Milestone 4: Parallelization (Week 2)
- [ ] Add genome splitting
- [ ] Add coordinate splitting
- [ ] Implement scatter-gather
- [ ] Performance testing

### Milestone 5: Production (Week 3-4)
- [ ] Error handling
- [ ] Resource optimization
- [ ] HPC testing
- [ ] Documentation

---

## 💡 Pro Tips

1. **Use `-resume`**: Nextflow caches results, so failed runs don't start from scratch
   ```bash
   nextflow run main.nf --genome ... -resume
   ```

2. **Check work directory**: All intermediate files are in `work/`
   ```bash
   ls -la work/
   ```

3. **Clean work directory**: Free up space after successful runs
   ```bash
   nextflow clean -f
   ```

4. **Use `-with-report`**: Get HTML report of execution
   ```bash
   nextflow run main.nf --genome ... -with-report report.html
   ```

---

## 🆘 If You Get Stuck

1. Check Nextflow docs: https://www.nextflow.io/docs/latest/
2. Look at work directory error logs
3. Simplify the process (remove complex commands)
4. Test commands manually first, then add to Nextflow

---

## ✅ Ready to Start!

As soon as Nextflow installation completes:
1. Run `nextflow run hello`
2. Run `nextflow run main.nf --help`
3. Start debugging PREPARE_GENOME process

**You're starting Phase 6 NOW - let's build this iteratively!** 🚀
