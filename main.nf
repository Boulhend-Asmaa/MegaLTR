#!/usr/bin/env nextflow

/*
 * MegaLTR Nextflow Pipeline
 * Phase 6: Production-Ready Workflow Automation
 *
 * Author: Asmaa Boulhend
 * Date: 2026-01-15
 * Version: 2.0
 *
 * This workflow orchestrates the complete MegaLTR pipeline for LTR
 * retrotransposon identification, classification, and analysis.
 *
 * Scientific equivalence: This Nextflow implementation produces identical
 * results to the optimized Bash pipeline, with added reproducibility,
 * parallelization, and HPC compatibility.
 */

nextflow.enable.dsl=2

// ============================================================================
// PARAMETER DEFINITIONS
// ============================================================================

params.genome = null
params.gff = null
params.outdir = "megaltr_results"
params.prefix = "results"

// Analysis type: 1=LTR detection only, 2=+insertion time, 3=+gene analysis, 4=LAI only
params.analysis_type = 3

// LTR detection parameters
params.trna = "Arabidopsis_thaliana_trna.fa"
params.min_ltr_len = 100
params.max_ltr_len = 7000
params.min_ltr_dist = 1000
params.max_ltr_dist = 15000
params.similarity = 85
params.match_pairs = 20

// TEsorter parameters
params.tesorter_db = "rexdb"
params.tesorter_cov = 20
params.tesorter_eval = 0.001
params.tesorter_rule = "80-80-80"
params.tesorter_hmm = "rexdb"

// Insertion time parameters
params.mutation_rate = 0.000000015  // Default for Arabidopsis

// Gene proximity parameters
params.upstream_dist = 5000
params.downstream_dist = 5000
params.density_window = 1000000
params.n_chromosomes = 9

// Execution parameters
params.threads = 4
params.help = false

// ============================================================================
// HELP MESSAGE
// ============================================================================

def helpMessage() {
    log.info"""
    ==============================================================
    MegaLTR Nextflow Pipeline v2.0
    ==============================================================

    Usage:
      nextflow run main.nf --genome <genome.fna> [options]

    Required arguments:
      --genome FILE           Input genome FASTA file

    Analysis modes (--analysis_type):
      1                      LTR detection and domain annotation only
      2                      Mode 1 + insertion time estimation
      3                      Mode 2 + gene chimera analysis (requires --gff)
      4                      LAI calculation only

    Optional arguments:
      --gff FILE             GFF annotation file (required for analysis_type=3)
      --outdir DIR           Output directory (default: megaltr_results)
      --prefix STR           Output file prefix (default: results)
      --threads INT          Number of threads (default: 4)

      LTR detection:
      --trna FILE            tRNA FASTA file (default: Arabidopsis_thaliana_trna.fa)
      --min_ltr_len INT      Min LTR length (default: 100)
      --max_ltr_len INT      Max LTR length (default: 7000)
      --min_ltr_dist INT     Min distance between LTRs (default: 1000)
      --max_ltr_dist INT     Max distance between LTRs (default: 15000)
      --similarity INT       Similarity threshold % (default: 85)

      TEsorter:
      --tesorter_db STR      Database {gydb,rexdb,rexdb-plant} (default: rexdb)
      --tesorter_rule STR    Classification rule (default: 80-80-80)

      Insertion time:
      --mutation_rate FLOAT  Neutral mutation rate (default: 1.5e-8)

      Gene analysis:
      --upstream_dist INT    Upstream distance (default: 5000)
      --downstream_dist INT  Downstream distance (default: 5000)

    Example:
      nextflow run main.nf \\
        --genome genome.fna \\
        --gff annotation.gff \\
        --analysis_type 3 \\
        --threads 8 \\
        -resume

    ==============================================================
    """.stripIndent()
}

if (params.help) {
    helpMessage()
    exit 0
}

// ============================================================================
// INPUT VALIDATION
// ============================================================================

if (!params.genome) {
    log.error "ERROR: --genome parameter is required"
    helpMessage()
    exit 1
}

if (params.analysis_type == 3 && !params.gff) {
    log.error "ERROR: --gff parameter is required for analysis_type=3"
    helpMessage()
    exit 1
}

// Log parameter values
log.info """
==============================================================
MegaLTR Nextflow Pipeline - Starting
==============================================================
Genome       : ${params.genome}
GFF          : ${params.gff ?: 'N/A'}
Analysis Type: ${params.analysis_type}
Output       : ${params.outdir}
Prefix       : ${params.prefix}
Threads      : ${params.threads}
==============================================================
"""

// ============================================================================
// PROCESS: PREPARE_GENOME
// Purpose: Validate FASTA format and simplify sequence IDs
// Input: Raw genome FASTA file
// Output: Cleaned genome, ID mapping table
// Scientific rationale: Simplified IDs prevent downstream tool failures
// ============================================================================

process PREPARE_GENOME {
    tag "Preparing ${genome.name}"
    publishDir "${params.outdir}/prepared", mode: 'copy', pattern: "${params.prefix}.mapping.txt"

    input:
    path genome

    output:
    path "${params.prefix}.fna", emit: genome
    path "${params.prefix}.mapping.txt", emit: mapping

    script:
    """
    # Validate FASTA format
    python3 ${projectDir}/bin/RUN/checkfasta.py ${genome}

    # Replace complex IDs with simple sequential IDs
    python3 ${projectDir}/bin/RUN/replaceIDs.py \\
        ${genome} '>\\S+' ${params.prefix}.mapping.txt

    # Remove extra annotations from headers (keeps only ID)
    sed 's/ .*//' ${genome} > ${params.prefix}.fna

    echo "[PREPARE_GENOME] Genome preparation complete"
    echo "  Original file: ${genome}"
    echo "  Sequences processed: \$(grep -c '^>' ${params.prefix}.fna)"
    """
}

// ============================================================================
// PROCESS: PREPARE_TRNA
// Purpose: Prepare tRNA database for LTR_FINDER
// Input: tRNA FASTA file
// Output: Cleaned tRNA file
// ============================================================================

process PREPARE_TRNA {
    tag "Preparing tRNA database"

    input:
    val trna_name

    output:
    path "${trna_name}", emit: trna

    script:
    """
    # Copy tRNA file and clean headers
    cp ${projectDir}/bin/tRNA/${trna_name} .
    sed -i 's/\\t.*//g' ${trna_name}

    echo "[PREPARE_TRNA] tRNA database prepared: ${trna_name}"
    """
}

// ============================================================================
// PROCESS: PREPARE_GFF
// Purpose: Validate and prepare GFF annotation file
// Input: Raw GFF file
// Output: Cleaned GFF file
// ============================================================================

process PREPARE_GFF {
    tag "Preparing ${gff.name}"

    input:
    path gff

    output:
    path "${params.prefix}.gff", emit: gff

    script:
    """
    cp ${gff} ${params.prefix}.gff

    echo "[PREPARE_GFF] GFF file prepared"
    echo "  Gene features: \$(grep -cP '\\tgene\\t' ${params.prefix}.gff || echo 0)"
    echo "  Pseudogene features: \$(grep -cP '\\tpseudogene\\t' ${params.prefix}.gff || echo 0)"
    """
}

// ============================================================================
// PROCESS: LTR_FINDER
// Purpose: Identify LTR retrotransposons using LTR_FINDER_parallel
// Input: Prepared genome FASTA, tRNA database
// Output: .scn file with LTR candidates
// Parallelization: Internal (splits genome into 1 Mb chunks)
// Scientific rationale: De novo LTR detection based on structural features
// ============================================================================

process LTR_FINDER {
    tag "LTR_FINDER detection"
    publishDir "${params.outdir}/ltr_finder", mode: 'copy', pattern: "*.scn"

    cpus params.threads

    input:
    path genome
    path trna

    output:
    path "${params.prefix}.fna.finder.combine.scn", emit: scn

    script:
    def similarity_finder = params.similarity / 100
    """
    # Run LTR_FINDER_parallel
    # -seq: input genome
    # -threads: parallel execution
    # -harvest_out: output format compatible with LTR_retriever
    # -size: split genome into 1 Mb chunks for parallelization
    # -time: max time per chunk (seconds)

    perl ${projectDir}/bin/LTR_FINDER_parallel/LTR_FINDER_parallel \\
        -seq ${genome} \\
        -threads ${task.cpus} \\
        -harvest_out \\
        -size 1000000 \\
        -time 500 \\
        ${projectDir}/bin/tRNA \\
        ${trna} \\
        ${params.max_ltr_dist} \\
        ${params.min_ltr_dist} \\
        ${params.max_ltr_len} \\
        ${params.min_ltr_len} \\
        ${params.match_pairs} \\
        ${similarity_finder} \\
        . \\
        ${params.similarity} \\
        ${params.prefix} \\
        > ltr_finder.log 2>&1

    echo "[LTR_FINDER] Detection complete"
    echo "  Candidates found: \$(grep -v '^#' ${params.prefix}.fna.finder.combine.scn | wc -l)"
    """
}

// ============================================================================
// PROCESS: LTR_HARVEST
// Purpose: Identify LTR retrotransposons using GenomeTools LTR_HARVEST
// Input: Prepared genome FASTA
// Output: .scn file with LTR candidates
// Parallelization: Internal (splits genome into 1 Mb chunks)
// Scientific rationale: Suffix array-based LTR detection (complementary to LTR_FINDER)
// ============================================================================

process LTR_HARVEST {
    tag "LTR_HARVEST detection"
    publishDir "${params.outdir}/ltr_harvest", mode: 'copy', pattern: "*.scn"

    cpus params.threads

    input:
    path genome

    output:
    path "${params.prefix}.fna.harvest.combine.scn", emit: scn

    script:
    """
    # Get conda environment path for genometools binary
    CONDA_PATH=\$(conda info --envs | grep "^MegaLTR " | awk '{print \$NF}')

    # Run LTR_HARVEST_parallel
    perl ${projectDir}/bin/LTR_HARVEST_parallel/LTR_HARVEST_parallel \\
        -seq ${genome} \\
        -threads ${task.cpus} \\
        -size 1000000 \\
        -time 500 \\
        -gt \${CONDA_PATH}/bin/gt \\
        ${params.min_ltr_len} \\
        ${params.max_ltr_len} \\
        ${params.similarity} \\
        > ltr_harvest.log 2>&1

    echo "[LTR_HARVEST] Detection complete"
    echo "  Candidates found: \$(grep -v '^#' ${params.prefix}.fna.harvest.combine.scn | wc -l)"
    """
}

// ============================================================================
// PROCESS: MERGE_LTR_CANDIDATES
// Purpose: Combine LTR_FINDER and LTR_HARVEST results
// Input: .scn files from both tools
// Output: Combined .scn file
// Scientific rationale: Union of two methods increases sensitivity
// ============================================================================

process MERGE_LTR_CANDIDATES {
    tag "Merging LTR candidates"

    input:
    path finder_scn
    path harvest_scn

    output:
    path "${params.prefix}.all.harvest.finder.combine", emit: combined

    script:
    """
    cat ${harvest_scn} ${finder_scn} > ${params.prefix}.all.harvest.finder.combine

    echo "[MERGE_LTR_CANDIDATES] Merging complete"
    echo "  Total candidates: \$(grep -v '^#' ${params.prefix}.all.harvest.finder.combine | wc -l)"
    """
}

// ============================================================================
// PROCESS: LTR_RETRIEVER
// Purpose: Filter and refine LTR candidates, calculate LAI
// Input: Combined LTR candidates, genome
// Output: High-quality LTR library, GFF3 annotation, LAI scores
// Scientific rationale: Removes false positives using LTR similarity,
//                      TSD presence, and protein domain evidence
// ============================================================================

process LTR_RETRIEVER {
    tag "LTR_retriever refinement"
    publishDir "${params.outdir}/ltr_retriever", mode: 'copy',
               pattern: "*.{list,gff3,out,LAI}"

    cpus params.threads

    input:
    path genome
    path combined_scn

    output:
    path "${params.prefix}.fna.pass.list", emit: pass_list, optional: true
    path "${params.prefix}.fna.nmtf.pass.list", emit: nmtf_list, optional: true
    path "${params.prefix}.fna.pass.list.gff3", emit: gff3, optional: true
    path "${params.prefix}.fna.out", emit: out_file, optional: true
    path "${params.prefix}.fna.out.LAI", emit: lai, optional: true
    path "${params.prefix}.fna.LTRlib.fa", emit: ltrlib_fa, optional: true
    path "screen.txt", emit: screen

    script:
    """
    # Run LTR_retriever
    # -genome: input genome
    # -inharvest: combined LTR candidates from both tools
    # -threads: parallel execution
    # -minlen: minimum LTR length filter

    ${projectDir}/bin/LTR_retriever/LTR_retriever \\
        -genome ${genome} \\
        -inharvest ${combined_scn} \\
        -threads ${task.cpus} \\
        -minlen ${params.min_ltr_len} \\
        > screen.txt 2>&1

    # Extract key metrics
    echo "[LTR_RETRIEVER] Processing complete"

    if [ -f "${params.prefix}.fna.pass.list" ]; then
        echo "  High-quality LTRs: \$(wc -l < ${params.prefix}.fna.pass.list)"
    fi

    if [ -f "${params.prefix}.fna.out.LAI" ]; then
        LAI=\$(grep "whole_genome" ${params.prefix}.fna.out.LAI | awk '{print \$7}')
        echo "  LAI (LTR Assembly Index): \${LAI}"
    fi
    """
}

// ============================================================================
// PROCESS: LTRDIGEST
// Purpose: Annotate internal protein domains in LTRs
// Input: LTR_retriever output, genome, tRNA
// Output: Annotated LTR sequences with domain information
// Scientific rationale: Identifies GAG, POL, ENV domains for classification
// ============================================================================

process LTRDIGEST {
    tag "LTRdigest annotation"
    publishDir "${params.outdir}/ltrdigest", mode: 'copy',
               pattern: "${params.prefix}_*.{fas,csv}"

    errorStrategy 'ignore'  // Skip if fails, continue workflow

    input:
    path genome
    path trna
    path pass_list

    output:
    path "${params.prefix}_complete.fas", emit: complete_fas, optional: true
    path "${params.prefix}_tabout.csv", emit: tabout, optional: true
    path "${params.prefix}_pbs.fas", emit: pbs, optional: true
    path "${params.prefix}_ppt.fas", emit: ppt, optional: true

    script:
    """
    # Step 1: Create suffix array index for genome
    gt suffixerator -db ${genome} -indexname ${params.prefix}.fna -tis -suf -lcp -des -ssp -sds -dna

    # Step 2: Prepare GFF3 file (normalize retrotransposon types and remove uppercase attributes)
    # Remove all uppercase attributes (Classification, Sequence_ontology, Method, Name)
    # gt ltrdigest reserves uppercase attributes and rejects them
    # Also normalize retrotransposon types for compatibility
    sed 's/;Classification=[^;]*//g' ${pass_list} | \\
        sed 's/;Sequence_ontology=[^;]*//g' | \\
        sed 's/;Method=[^;]*//g' | \\
        sed 's/;Name=[^;]*//g' | \\
        sed 's/Copia_LTR_retrotransposon/LTR_retrotransposon/g' | \\
        sed 's/Gypsy_LTR_retrotransposon/LTR_retrotransposon/g' > normalized.gff3

    # Step 3: Run LTRdigest with protein domain annotation
    gt -j ${task.cpus} ltrdigest \\
        -trnas ${trna} \\
        -outfileprefix ${params.prefix} \\
        normalized.gff3 \\
        ${params.prefix}.fna \\
        > ${params.prefix}_ltrdigest.gff3

    echo "[LTRDIGEST] Domain annotation complete"
    echo "  Annotated sequences: \$(grep -c '^>' ${params.prefix}_complete.fas 2>/dev/null || echo 0)"
    """
}

// ============================================================================
// PROCESS: TESORTER
// Purpose: Classify LTRs into superfamilies and clades
// Input: LTRdigest annotated sequences
// Output: Classification table with superfamily/clade assignments
// Scientific rationale: Uses HMM profiles of RT domains for phylogenetic classification
// ============================================================================

process TESORTER {
    tag "TEsorter classification"
    publishDir "${params.outdir}/tesorter", mode: 'copy',
               pattern: "*.cls.tsv"

    cpus params.threads

    input:
    path complete_fas

    output:
    path "*.cls.tsv", emit: cls_tsv

    script:
    """
    # Run TEsorter wrapper script
    bash ${projectDir}/bin/RUN/TEsorter.sh \\
        . \\
        ${complete_fas} \\
        ${params.tesorter_db} \\
        ${params.tesorter_cov} \\
        ${params.tesorter_eval} \\
        ${params.tesorter_rule} \\
        ${params.tesorter_hmm} \\
        ${projectDir}/bin/RUN \\
        ${params.prefix} \\
        . \\
        . \\
        ${task.cpus}

    echo "[TESORTER] Classification complete"
    echo "  Classified elements: \$(wc -l < *.cls.tsv)"
    """
}

// ============================================================================
// PROCESS: MERGE_RESULTS
// Purpose: Combine LTR_retriever, LTRdigest, and TEsorter results
// Input: LTRdigest tabout, TEsorter classification
// Output: Integrated results table
// Scientific rationale: Single comprehensive table with structure + classification
// ============================================================================

process MERGE_RESULTS {
    tag "Merging results"
    publishDir "${params.outdir}/results", mode: 'copy'

    input:
    path tabout
    path cls_tsv
    path pass_list

    output:
    path "LTR_Table_TEsorter_Digest.tsv", emit: merged_table
    path "${params.prefix}.statistics.tsv", emit: statistics
    path "${params.prefix}.ids.extract_seq", emit: extract_coords

    script:
    """
    # Filter LTR vs non-LTR elements
    awk -F '\\t' '\$2 == "LTR"' ${cls_tsv} > ${params.prefix}.LTR.tsv
    awk -F '\\t' '\$2 != "LTR"' ${cls_tsv} > ${params.prefix}.others.tsv

    # Check if tabout has data (LTRDIGEST succeeded) or is empty (LTRDIGEST failed)
    if [ -s ${tabout} ] && [ "\$(wc -l < ${tabout})" -gt 0 ]; then
        echo "[MERGE_RESULTS] Using LTRDIGEST tabout data"
        # Convert tabout to TSV
        perl ${projectDir}/bin/RUN/print.pl ${tabout} > ${params.prefix}.tabout.tsv

        # Merge LTRdigest and TEsorter results
        perl ${projectDir}/bin/RUN/TEsorter_Digest.pl \\
            ${params.prefix}.tabout.tsv \\
            ${params.prefix}.LTR.tsv \\
            > 2LTR_Table_TEsorter_Digest.tsv
    else
        echo "[MERGE_RESULTS] LTRDIGEST unavailable, using merge_retriever_tesorter.py"
        # Use Python script to merge LTR_retriever pass.list with TEsorter classification
        # This creates proper 37-column output compatible with classification_NEW_LTR_2.py
        python3 ${projectDir}/bin/RUN/merge_retriever_tesorter.py \\
            ${pass_list} \\
            ${params.prefix}.LTR.tsv \\
            2LTR_Table_TEsorter_Digest.tsv
    fi

    # Check if we have data to process
    if [ ! -s 2LTR_Table_TEsorter_Digest.tsv ]; then
        echo "[MERGE_RESULTS] WARNING: No LTR elements found, creating empty output files"
        touch LTR_Table_TEsorter_Digest.tsv
        touch ${params.prefix}.statistics.tsv
        touch ${params.prefix}.ids.extract_seq
    else
        # Classify and reformat
        python3 ${projectDir}/bin/RUN/classification_NEW_LTR_2.py \\
            2LTR_Table_TEsorter_Digest.tsv \\
            new_LTR_Table_TEsorter_Digest.tsv

        # Reorder columns
        awk -F'\\t' '{print \$2"\\t"\$3"\\t"\$4"\\t"\$5"\\t"\$6"\\t"\$7"\\t"\$8"\\t"\$9"\\t"\$10"\\t"\$11"\\t"\$12"\\t"\$13"\\t"\$14"\\t"\$15"\\t"\$16"\\t"\$17"\\t"\$18"\\t"\$19"\\t"\$20"\\t"\$21"\\t"\$22"\\t"\$23"\\t"\$24"\\t"\$25"\\t"\$26"\\t"\$27"\\t"\$28"\\t"\$29"\\t"\$30"\\t"\$31"\\t"\$32"\\t"\$33"\\t"\$1"\\t"\$35"\\t"\$36"\\t"\$37"\\t"\$38}' \\
            new_LTR_Table_TEsorter_Digest.tsv > LTR_Table_TEsorter_Digest.tsv

        # Generate superfamily statistics
        awk -F "\\t" '{print \$2"\\t"\$33"\\t"\$3"\\t"\$4"\\t"\$5}' \\
            LTR_Table_TEsorter_Digest.tsv > ${params.prefix}.length.ids.forstat

        python3 ${projectDir}/bin/RUN/super_familly_stat.py \\
            ${params.prefix}.length.ids.forstat \\
            ${params.prefix}.statistics.tsv

        # Extract coordinates for sequence extraction
        awk -F "\\t" '{print \$2"\\t"\$3"\\t"\$4"\\t"\$5"\\t"\$32"\\t"\$33"\\t"\$34}' \\
            LTR_Table_TEsorter_Digest.tsv > ${params.prefix}.ids.extract_seq
    fi

    echo "[MERGE_RESULTS] Integration complete"
    echo "  Total LTR elements: \$(wc -l < LTR_Table_TEsorter_Digest.tsv)"
    """
}

// ============================================================================
// PROCESS: SPLIT_COORDINATES
// Purpose: Split coordinate file for parallel sequence extraction
// Input: Coordinate list (chr, start, end, etc.)
// Output: Multiple chunk files for parallel processing
// Parallelization: Phase 5 adaptive TSV splitting - NO EMPTY FILES
// Scientific rationale: Small genomes need fewer chunks (avoids empty files)
// ============================================================================

process SPLIT_COORDINATES {
    tag "Splitting ${extract_coords.name}"

    input:
    path extract_coords

    output:
    path "chunk*", emit: chunks

    script:
    """
    # Use Phase 5 smart_split_tsv.py (adaptive chunking algorithm)
    # - For small inputs: min(lines, threads × 4) chunks
    # - For large inputs: min(100, lines / 10) chunks
    # - Guarantee: ZERO empty chunk files

    python3 ${projectDir}/bin/RUN/smart_split_tsv.py \\
        ${extract_coords} \\
        . \\
        --threads ${params.threads} \\
        --prefix chunk

    CHUNK_COUNT=\$(ls -1 chunk* 2>/dev/null | wc -l)
    echo "[SPLIT_COORDINATES] Created \${CHUNK_COUNT} chunks (Phase 5 adaptive algorithm)"

    # Verify no empty chunks
    EMPTY_COUNT=\$(find . -name 'chunk*' -empty | wc -l)
    if [ \${EMPTY_COUNT} -gt 0 ]; then
        echo "ERROR: Found \${EMPTY_COUNT} empty chunks (should be zero!)"
        exit 1
    fi
    echo "  Validation: 0 empty chunks (Phase 5 guarantee)"
    """
}

// ============================================================================
// PROCESS: EXTRACT_SEQUENCES
// Purpose: Extract LTR sequences from genome using coordinates
// Input: Genome, coordinate chunks
// Output: FASTA file with all LTR sequences
// Parallelization: Uses Phase 5 chunks (scatter-gather pattern)
// Scientific rationale: Extracts actual nucleotide sequences for downstream analysis
// ============================================================================

process EXTRACT_SEQUENCES {
    tag "Extracting sequences (${chunks.size()} chunks)"
    publishDir "${params.outdir}/results", mode: 'copy',
               pattern: "LTR-RT_Sequence.fa"

    cpus params.threads

    input:
    path genome
    path chunks

    output:
    path "LTR-RT_Sequence.fa", emit: sequences

    script:
    """
    # Create chunk directory
    mkdir -p chunks
    mv chunk* chunks/ 2>/dev/null || true

    # Run parallel sequence extraction
    # LTR_Seq_threads.py supports both chunk* (new) and x* (old) naming
    python3 ${projectDir}/bin/RUN/LTR_Seq_threads.py \\
        ${genome} \\
        chunks \\
        . \\
        ${task.cpus} \\
        ${projectDir}/bin/RUN/extractseq-id-start-end.pl

    echo "[EXTRACT_SEQUENCES] Extraction complete"
    echo "  Sequences extracted: \$(grep -c '^>' LTR-RT_Sequence.fa)"
    """
}

// ============================================================================
// PROCESS: BUILD_NONREDUNDANT_LIBRARY
// Purpose: Cluster LTR sequences at 90% identity to remove redundancy
// Input: All LTR sequences
// Output: Non-redundant LTR library
// Scientific rationale: Removes recent duplications, creates representative library
// Tool: vsearch (replaces deprecated usearch in original pipeline)
// ============================================================================

process BUILD_NONREDUNDANT_LIBRARY {
    tag "Building non-redundant library"
    publishDir "${params.outdir}/results", mode: 'copy'

    input:
    path sequences

    output:
    path "LTR-RTs_non-redundant_library.fasta", emit: library
    path "usearch.log", emit: log

    script:
    """
    # Sort by length (longest first) using vsearch
    vsearch \\
        --sortbylength ${sequences} \\
        --output LTR-RT_Sequence_sorted.fa \\
        2>&1 | tee usearch.log

    # Cluster at 90% identity (keeps centroids) using vsearch
    vsearch \\
        --cluster_fast LTR-RT_Sequence_sorted.fa \\
        --id 0.9 \\
        --centroids LTR-RTs_non-redundant_library.fasta \\
        --uc result.uc \\
        2>&1 | tee usearch2.log

    cat usearch2.log >> usearch.log

    echo "[BUILD_NONREDUNDANT_LIBRARY] Clustering complete"
    echo "  Input sequences: \$(grep -c '^>' ${sequences})"
    echo "  Non-redundant library: \$(grep -c '^>' LTR-RTs_non-redundant_library.fasta)"
    """
}

// ============================================================================
// PROCESS: CALCULATE_INSERTION_TIME
// Purpose: Estimate LTR insertion age using LTR divergence
// Input: Genome, merged results table
// Output: Table with insertion time estimates
// Scientific rationale: 5' and 3' LTRs are identical at insertion, divergence
//                      measures time since transposition
// Method: Kimura 2-parameter and Tajima-Nei substitution models
// ============================================================================

process CALCULATE_INSERTION_TIME {
    tag "Calculating insertion times"
    publishDir "${params.outdir}/results", mode: 'copy'

    input:
    path genome
    path merged_table

    output:
    path "${params.prefix}.Digest_TEsorter_Time.tsv", emit: time_table
    path "time/*.aln", emit: alignments, optional: true

    script:
    """
    mkdir -p time

    # Extract LTR regions for each element
    python3 ${projectDir}/bin/RUN/get_region.py \\
        ${genome} \\
        ${merged_table} \\
        time

    # Calculate insertion time for each LTR
    echo "" > ${params.prefix}.time.txt
    echo "LTRNAME\tK_Kimura\tK_Ksd\tK_TajimaNei\tK_TNsd\ttimeK\ttimeKsd\tnumComparedSites\ttransitions\tnumComparedSites\ttransversions\tnumComparedSites\ttimeTN\ttransitions_numComparedSites\ttransversions_numComparedSites" >> ${params.prefix}.time.txt

    for fst in time/*.fasta; do
        if [ -f "\$fst" ]; then
            # Align 5' and 3' LTRs using ClustalW
            clustalw -infile="\$fst" >> clustalw.log 2>&1

            # Estimate divergence (K) and insertion time
            fname=\$(basename "\$fst" ".fasta")
            ltrk=\$(perl ${projectDir}/bin/RUN/estimate_K.pl \\
                time/\${fname}.aln \\
                ${params.mutation_rate})

            echo -e "\$fname\t\$ltrk" >> ${params.prefix}.time.txt
        fi
    done

    # Merge with classification table
    perl ${projectDir}/bin/RUN/TEsorterandtable_time.pl \\
        ${merged_table} \\
        ${params.prefix}.time.txt \\
        > ${params.prefix}.Digest_TEsorter_Time.tsv

    echo "[CALCULATE_INSERTION_TIME] Time estimation complete"
    echo "  Elements dated: \$(wc -l < ${params.prefix}.time.txt)"
    """
}

// ============================================================================
// PROCESS: GENERATE_TIME_PLOTS
// Purpose: Visualize LTR insertion time and length distributions
// Input: Time table
// Output: PNG plots of insertion age by superfamily
// Scientific rationale: Reveals transposition burst periods
// ============================================================================

process GENERATE_TIME_PLOTS {
    tag "Generating R plots"
    publishDir "${params.outdir}/results", mode: 'copy', pattern: "*.png"

    input:
    path time_table

    output:
    path "*.png", emit: plots

    script:
    """
    mkdir -p plots

    # Prepare data for plotting
    awk -F "\\t" '{print \$1"\\t"\$33"\\t"\$42}' ${time_table} > plots/${params.prefix}.time.ids
    awk -F "\\t" '{print \$2"\\t"\$33"\\t"\$3"\\t"\$4"\\t"\$5}' ${time_table} > plots/${params.prefix}.length.ids

    # By superfamily
    awk -F "\\t" '{print \$1"\\t""Autonomous and Nonautonomous""\\t"\$3}' \\
        plots/${params.prefix}.time.ids > plots/${params.prefix}.time.ids2

    awk -F "\\t" '{print \$1"\\t""Autonomous and Nonautonomous""\\t"\$2"\\t"\$3"\\t"\$4"\\t"\$5}' \\
        plots/${params.prefix}.length.ids > plots/${params.prefix}.length.ids2

    # Generate plots
    Rscript ${projectDir}/bin/RUN/chart_plot.r \\
        plots/${params.prefix}.length.ids \\
        plots/${params.prefix}.time.ids \\
        MegaLTR..${params.prefix} \\
        ${projectDir}/bin/RUN \\
        2>/dev/null || true

    Rscript ${projectDir}/bin/RUN/chart_plot.r \\
        plots/${params.prefix}.length.ids2 \\
        plots/${params.prefix}.time.ids2 \\
        MegaLTR..${params.prefix} \\
        ${projectDir}/bin/RUN \\
        2>/dev/null || true

    # Copy plots to output
    cp plots/*.png . 2>/dev/null || true

    echo "[GENERATE_TIME_PLOTS] Plotting complete"
    echo "  Plots generated: \$(ls -1 *.png 2>/dev/null | wc -l)"
    """
}

// ============================================================================
// PROCESS: IDENTIFY_GENE_CHIMERAS
// Purpose: Identify LTR-gene chimeric transcripts
// Input: Time table, GFF annotation
// Output: Table with LTRs inside/outside gene boundaries
// Scientific rationale: LTRs within genes may create chimeric transcripts
// ============================================================================

process IDENTIFY_GENE_CHIMERAS {
    tag "Identifying gene chimeras"
    publishDir "${params.outdir}/results", mode: 'copy'

    input:
    path time_table
    path gff

    output:
    path "LTR_Table_Digest_TEsorter_Time_nongene_and_gene.tsv", emit: chimera_table

    script:
    """
    # Extract gene and pseudogene annotations
    grep -P '\\tgene\\t' ${gff} > gene.gff || touch gene.gff
    grep -P '\\tpseudogene\\t' ${gff} > pseudogene.gff || touch pseudogene.gff
    cat gene.gff pseudogene.gff > gene_pseudogene.gff

    # Identify LTRs within gene boundaries
    perl ${projectDir}/bin/RUN/get-TE-within-gene.pl \\
        ${time_table} \\
        gene_pseudogene.gff \\
        ${params.prefix} \\
        . \\
        > LTR_inside_genes.table

    # Identify LTRs outside genes
    awk -F "\\t" '{print \$1}' LTR_inside_genes.table > inside.ids
    awk -F "\\t" '{print \$1}' ${time_table} > all.ids

    grep -F -x -v -f inside.ids all.ids > outside.ids
    grep -f outside.ids ${time_table} > LTR_Table_nongene1

    perl ${projectDir}/bin/RUN/No.pl LTR_Table_nongene1 > LTR_Table_nongene

    # Combine inside and outside
    cat LTR_inside_genes.table LTR_Table_nongene > LTR_Table_Digest_TEsorter_Time_nongene_and_gene.tsv

    # Add header
    sed -i '1i LTR-RT id\\tPseudomolecules/scaffolds\\tLTR-RT start\\tLTR-RT end\\tLTR-RT length\\tlLTR start\\tlLTR end\\tlLTR length\\trLTR start\\trLTR end\\trLTR length\\tlTSD start\\tlTSD end\\tlTSD sequence\\trTSD start\\trTSD end\\trTSD sequence\\tPPT start\\tPPT end\\tPPT motif\\tStrand\\tPPT offset\\tPBS start\\tPBS end\\tStrand\\ttRNA id\\ttRNA motif\\tPBS offset\\ttRNA offset\\tPBS/tRNA\\tClass\\tSuperfamily\\tClade\\tComplete\\tStrand\\tDomains\\tK_Kimura\\tK_Ksd\\tK_TajimaNei\\tK_TNsd\\ttimeK\\ttimeKsd\\tnumComparedSites\\ttransitions\\tnumComparedSites\\ttransversions\\tnumComparedSites\\ttimeTN\\ttransitions_numComparedSites\\ttransversions_numComparedSites\\tinside gene status\\tgene/pseudogene\\tGene start\\tGene end\\tstrand\\tgene annotation' LTR_Table_Digest_TEsorter_Time_nongene_and_gene.tsv

    echo "[IDENTIFY_GENE_CHIMERAS] Analysis complete"
    echo "  LTRs inside genes: \$(wc -l < inside.ids)"
    echo "  LTRs outside genes: \$(wc -l < outside.ids)"
    """
}

// ============================================================================
// PROCESS: FIND_NEARBY_GENES
// Purpose: Identify genes near LTRs (upstream/downstream)
// Input: Time table, GFF annotation
// Output: Table with nearby genes (within specified distance)
// Scientific rationale: LTR insertions may affect nearby gene expression
// ============================================================================

process FIND_NEARBY_GENES {
    tag "Finding nearby genes"
    publishDir "${params.outdir}/results", mode: 'copy'

    input:
    path time_table
    path gff

    output:
    path "${params.prefix}.genes_up_and_down_LTR.tsv", emit: nearby_genes

    script:
    """
    # Extract gene and pseudogene annotations
    grep -P '\\tgene\\t' ${gff} > gene.gff || touch gene.gff
    grep -P '\\tpseudogene\\t' ${gff} > pseudogene.gff || touch pseudogene.gff
    cat gene.gff pseudogene.gff > gene_pseudogene.gff

    # Replace unknown strand with +
    sed 's/\\t?\\t/\\t+\\t/g' gene_pseudogene.gff > gene_pseudogene2.gff
    sed 's/\\t?\\t/\\t+\\t/g' ${time_table} > time_table2.tsv

    # Separate by strand
    awk -F '\\t' '\$36=="+"' time_table2.tsv > time_plus.tsv
    awk -F '\\t' '\$36=="-"' time_table2.tsv > time_minus.tsv

    # Find nearby genes (strand-aware)
    perl ${projectDir}/bin/RUN/get-TE-near-gene-minuse1k.pl \\
        time_plus.tsv gene_pseudogene2.gff \\
        ${params.upstream_dist} ${params.downstream_dist} > up_genes_plus

    perl ${projectDir}/bin/RUN/get-TE-near-gene-pluse-1k.pl \\
        time_plus.tsv gene_pseudogene2.gff \\
        ${params.upstream_dist} ${params.downstream_dist} > down_genes_plus

    perl ${projectDir}/bin/RUN/get-TE-near-gene-minuse-1k.pl \\
        time_minus.tsv gene_pseudogene2.gff \\
        ${params.upstream_dist} ${params.downstream_dist} > down_genes_minus

    perl ${projectDir}/bin/RUN/get-TE-near-gene-pluse+1k.pl \\
        time_minus.tsv gene_pseudogene2.gff \\
        ${params.upstream_dist} ${params.downstream_dist} > up_genes_minus

    # Combine all results
    cat up_genes_plus down_genes_plus down_genes_minus up_genes_minus > genes_up_and_down_LTR.tsv

    # Add header
    cp genes_up_and_down_LTR.tsv ${params.prefix}.genes_up_and_down_LTR.tsv
    sed -i '1i LTR-RT id\\tUp/Downstream\\tPseudomolecules/scaffolds\\tLTR-RT start\\tLTR-RT end\\tLTR-RT length\\tlLTR start\\tlLTR end\\tlLTR length\\trLTR start\\trLTR end\\trLTR length\\tlTSD start\\tlTSD end\\tlTSD sequence\\trTSD start\\trTSD end\\trTSD sequence\\tPPT start\\tPPT end\\tPPT motif\\tStrand\\tPPT offset\\tPBS start\\tPBS end\\tStrand\\ttRNA id\\ttRNA motif\\tPBS offset\\ttRNA offset\\tPBS/tRNA\\t\\tClass\\tSuperfamily\\tClade\\tComplete\\tStrand\\tDomains\\tK_Kimura\\tK_Ksd\\tK_TajimaNei\\tK_TNsd\\ttimeK\\ttimeKsd\\tnumComparedSites\\ttransitions\\tnumComparedSites\\ttransversions\\tnumComparedSites\\ttimeTN\\ttransitions_numComparedSites\\ttransversions_numComparedSites\\tgene/pseudogene\\tGene start\\tGene end\\tgene length\\tstrand\\tgene annotation' ${params.prefix}.genes_up_and_down_LTR.tsv

    echo "[FIND_NEARBY_GENES] Analysis complete"
    echo "  LTRs with nearby genes: \$(wc -l < genes_up_and_down_LTR.tsv)"
    """
}

// ============================================================================
// PROCESS: VISUALIZE_CHROMOSOME_DENSITY
// Purpose: Generate chromosome karyotype plots with gene/LTR density
// Input: Time table, GFF annotation
// Output: SVG/PNG plots of LTR distribution across chromosomes
// Scientific rationale: Reveals non-random distribution patterns (e.g., centromeres)
// ============================================================================

process VISUALIZE_CHROMOSOME_DENSITY {
    tag "Visualizing chromosome density"
    publishDir "${params.outdir}/results", mode: 'copy', pattern: "*.{svg,png,tsv}"

    input:
    path time_table
    path gff

    output:
    path "Gene density and LTR-RTs distribution.svg", emit: svg, optional: true
    path "Gene density and LTR-RTs distribution.png", emit: png, optional: true
    path "Map of Gene density and LTR-RTs distribution Figure.tsv", emit: map, optional: true

    script:
    """
    mkdir -p density

    # Prepare LTR distribution data
    awk -F "\\t" '{print \$33"\\t"\$33"\\t"\$2"\\t"\$3"\\t"\$4"\\t"\$33}' \\
        ${time_table} > density/figure.distrbution1

    # Format superfamily names and assign colors
    sed -i -E 's/Autonomous://g; s/Nonautonomous://g' density/figure.distrbution1

    # Copia = purple triangle
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("Copia","triangle",\$2);print}' density/figure.distrbution1 > density/figure.distrbution2
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("Copia","6a3d9a",\$6);print}' density/figure.distrbution2 > density/figure.distrbution3

    # Gypsy = green triangle
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("Gypsy","triangle",\$2);print}' density/figure.distrbution3 > density/figure.distrbution4
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("Gypsy","33a02c",\$6);print}' density/figure.distrbution4 > density/figure.distrbution5

    # BARE-2 = orange triangle
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("BARE-2","triangle",\$2);print}' density/figure.distrbution5 > density/figure.distrbution6
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("BARE-2","ff7f00",\$6);print}' density/figure.distrbution6 > density/figure.distrbution7

    # TR-GAG = pink triangle
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("TR-GAG","triangle",\$2);print}' density/figure.distrbution7 > density/figure.distrbution8
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("TR-GAG","ff0080",\$6);print}' density/figure.distrbution8 > density/figure.distrbution9

    # Unknown = brown triangle
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("Unknown","triangle",\$2);print}' density/figure.distrbution9 > density/figure.distrbution10
    awk -F '\\t' 'BEGIN{OFS=FS}{gsub("Unknown","9d8477",\$6);print}' density/figure.distrbution10 > density/figure.distrbution11

    # Extract karyotype from GFF
    grep "##sequence-region" ${gff} > density/karyotype || touch density/karyotype
    sed -i 's/##sequence-region //g; s/ /\\t/g' density/karyotype

    # Calculate gene density
    grep -P '\\tgene\\t|\\tpseudogene\\t' ${gff} | \\
        awk -F "\\t" '{print \$1"\\t"\$4"\\t"\$5"\\t1"}' > density/gene_anno

    python3 ${projectDir}/bin/RUN/counter.py \\
        density/gene_anno \\
        ${params.density_window} \\
        density/gene_anno_counter

    # Sort by chromosome length and select top N
    sort -k3,3nr density/karyotype > density/karyotype_sort

    echo "Chr\\tStart\\tEnd" > density/karyotype_sort_head
    head -${params.n_chromosomes} density/karyotype_sort >> density/karyotype_sort_head

    awk -F "\\t" '{print \$1}' density/karyotype_sort_head > density/chr.ids

    # Filter data for selected chromosomes
    echo "Chr\\tStart\\tEnd\\tValue" > density/gene_anno_counter_ok
    grep -f density/chr.ids density/gene_anno_counter >> density/gene_anno_counter_ok || true

    echo "Type\\tShape\\tChr\\tStart\\tEnd\\tcolor" > density/figure_distrbution_ok
    grep -f density/chr.ids density/figure.distrbution11 >> density/figure_distrbution_ok || true

    # Generate legend mapping
    python3 ${projectDir}/bin/RUN/figure_legend.py \\
        density/figure_distrbution_ok \\
        density/gene_anno_counter_ok \\
        density/karyotype_sort_head \\
        "Map of Gene density and LTR-RTs distribution Figure.tsv"

    # Generate plots (choose script based on chromosome count)
    cd density
    if [ ${params.n_chromosomes} -le 8 ]; then
        Rscript ${projectDir}/bin/RUN/density_width.r \\
            karyotype_sort_head \\
            gene_anno_counter_ok \\
            figure_distrbution_ok \\
            2>/dev/null || true
    else
        Rscript ${projectDir}/bin/RUN/density.r \\
            karyotype_sort_head \\
            gene_anno_counter_ok \\
            figure_distrbution_ok \\
            2>/dev/null || true
    fi
    cd ..

    # Copy outputs
    cp density/chromosome.svg "Gene density and LTR-RTs distribution.svg" 2>/dev/null || true
    cp density/chromosome.png "Gene density and LTR-RTs distribution.png" 2>/dev/null || true

    echo "[VISUALIZE_CHROMOSOME_DENSITY] Visualization complete"
    """
}

// ============================================================================
// PROCESS: RESTORE_IDS
// Purpose: Restore original sequence IDs in final outputs
// Input: Any output file with simplified IDs, mapping table
// Output: File with original IDs restored
// Scientific rationale: Users need original sequence names for interpretation
// ============================================================================

process RESTORE_IDS {
    tag "Restoring original IDs"
    publishDir "${params.outdir}/results", mode: 'copy'

    input:
    path mapping
    path merged_table
    path sequences
    path library
    path pbs
    path ppt
    path time_table
    path chimera_table
    path nearby_genes
    path pass_list
    path nmtf_list
    path gff3
    path out_file

    output:
    path "*.restored", emit: restored_files

    script:
    """
    # Restore IDs in all output files

    if [ -f "${merged_table}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${merged_table} ${mapping} 2
        mv ${merged_table} ${merged_table}.restored
    fi

    if [ -f "${sequences}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${sequences} ${mapping} 2
        mv ${sequences} ${sequences}.restored
    fi

    if [ -f "${library}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${library} ${mapping} 2
        mv ${library} ${library}.restored
    fi

    if [ -f "${pbs}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${pbs} ${mapping} 2
        mv ${pbs} ${pbs}.restored
    fi

    if [ -f "${ppt}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${ppt} ${mapping} 2
        mv ${ppt} ${ppt}.restored
    fi

    if [ -f "${time_table}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${time_table} ${mapping} 2
        mv ${time_table} ${time_table}.restored
    fi

    if [ -f "${chimera_table}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${chimera_table} ${mapping} 2
        mv ${chimera_table} ${chimera_table}.restored
    fi

    if [ -f "${nearby_genes}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${nearby_genes} ${mapping} 2
        mv ${nearby_genes} ${nearby_genes}.restored
    fi

    if [ -f "${pass_list}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${pass_list} ${mapping} 2
        mv ${pass_list} ${pass_list}.restored
    fi

    if [ -f "${nmtf_list}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${nmtf_list} ${mapping} 2
        mv ${nmtf_list} ${nmtf_list}.restored
    fi

    if [ -f "${gff3}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${gff3} ${mapping} 2
        mv ${gff3} ${gff3}.restored
    fi

    if [ -f "${out_file}" ]; then
        python3 ${projectDir}/bin/RUN/modifyGFF.py ${out_file} ${mapping} 2
        mv ${out_file} ${out_file}.restored
    fi

    echo "[RESTORE_IDS] ID restoration complete"
    echo "  Files processed: \$(ls -1 *.restored | wc -l)"
    """
}

// ============================================================================
// WORKFLOW: Main pipeline orchestration
// ============================================================================

workflow {

    // ========================================================================
    // STAGE 1: Input preparation
    // ========================================================================

    genome_ch = Channel.fromPath(params.genome, checkIfExists: true)

    PREPARE_GENOME(genome_ch)
    PREPARE_TRNA(params.trna)

    // ========================================================================
    // STAGE 2: LTR detection (parallel)
    // ========================================================================

    LTR_FINDER(
        PREPARE_GENOME.out.genome,
        PREPARE_TRNA.out.trna
    )

    LTR_HARVEST(
        PREPARE_GENOME.out.genome
    )

    MERGE_LTR_CANDIDATES(
        LTR_FINDER.out.scn,
        LTR_HARVEST.out.scn
    )

    // ========================================================================
    // STAGE 3: LTR refinement and domain annotation
    // ========================================================================

    LTR_RETRIEVER(
        PREPARE_GENOME.out.genome,
        MERGE_LTR_CANDIDATES.out.combined
    )

    if (params.analysis_type >= 1) {
        LTRDIGEST(
            PREPARE_GENOME.out.genome,
            PREPARE_TRNA.out.trna,
            LTR_RETRIEVER.out.gff3
        )

        // Use LTRDIGEST output if available, otherwise fall back to LTR_RETRIEVER library
        ltr_sequences = LTRDIGEST.out.complete_fas
            .mix(LTR_RETRIEVER.out.ltrlib_fa)
            .first()

        TESORTER(
            ltr_sequences
        )

        // ====================================================================
        // STAGE 4: Result integration and sequence extraction
        // ====================================================================

        // Create empty tabout if LTRDIGEST failed
        ltrdigest_tabout = LTRDIGEST.out.tabout
            .ifEmpty(file("${projectDir}/bin/RUN/empty.tabout.csv"))

        MERGE_RESULTS(
            ltrdigest_tabout,
            TESORTER.out.cls_tsv,
            LTR_RETRIEVER.out.pass_list
        )

        // Phase 5 TSV splitting for parallel sequence extraction
        SPLIT_COORDINATES(
            MERGE_RESULTS.out.extract_coords
        )

        EXTRACT_SEQUENCES(
            PREPARE_GENOME.out.genome,
            SPLIT_COORDINATES.out.chunks.collect()
        )

        BUILD_NONREDUNDANT_LIBRARY(
            EXTRACT_SEQUENCES.out.sequences
        )

        // ====================================================================
        // STAGE 5: Insertion time analysis (optional)
        // ====================================================================

        if (params.analysis_type >= 2) {
            CALCULATE_INSERTION_TIME(
                PREPARE_GENOME.out.genome,
                MERGE_RESULTS.out.merged_table
            )

            GENERATE_TIME_PLOTS(
                CALCULATE_INSERTION_TIME.out.time_table
            )

            // ================================================================
            // STAGE 6: Gene association analysis (optional)
            // ================================================================

            if (params.analysis_type >= 3) {
                gff_ch = Channel.fromPath(params.gff, checkIfExists: true)
                PREPARE_GFF(gff_ch)

                IDENTIFY_GENE_CHIMERAS(
                    CALCULATE_INSERTION_TIME.out.time_table,
                    PREPARE_GFF.out.gff
                )

                FIND_NEARBY_GENES(
                    CALCULATE_INSERTION_TIME.out.time_table,
                    PREPARE_GFF.out.gff
                )

                VISUALIZE_CHROMOSOME_DENSITY(
                    CALCULATE_INSERTION_TIME.out.time_table,
                    PREPARE_GFF.out.gff
                )

                // ============================================================
                // STAGE 7: Restore original IDs in all outputs
                // ============================================================

                RESTORE_IDS(
                    PREPARE_GENOME.out.mapping,
                    MERGE_RESULTS.out.merged_table,
                    EXTRACT_SEQUENCES.out.sequences,
                    BUILD_NONREDUNDANT_LIBRARY.out.library,
                    LTRDIGEST.out.pbs,
                    LTRDIGEST.out.ppt,
                    CALCULATE_INSERTION_TIME.out.time_table,
                    IDENTIFY_GENE_CHIMERAS.out.chimera_table,
                    FIND_NEARBY_GENES.out.nearby_genes,
                    LTR_RETRIEVER.out.pass_list,
                    LTR_RETRIEVER.out.nmtf_list,
                    LTR_RETRIEVER.out.gff3,
                    LTR_RETRIEVER.out.out_file
                )
            }
        }
    }
}

// ============================================================================
// WORKFLOW COMPLETION HANDLER
// ============================================================================

workflow.onComplete {
    log.info """
    ==============================================================
    MegaLTR Pipeline Complete!
    ==============================================================
    Status       : ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Duration     : ${workflow.duration}
    Analysis Type: ${params.analysis_type}
    Output Dir   : ${params.outdir}
    ==============================================================

    Key outputs:
    - LTR-RT library         : ${params.outdir}/results/LTR-RTs_non-redundant_library.fasta
    - Annotation table       : ${params.outdir}/results/LTR_Table_TEsorter_Digest.tsv
    - Statistics             : ${params.outdir}/results/${params.prefix}.statistics.tsv
    ${params.analysis_type >= 2 ? "- Insertion times        : ${params.outdir}/results/${params.prefix}.Digest_TEsorter_Time.tsv" : ""}
    ${params.analysis_type >= 3 ? "- Gene chimeras          : ${params.outdir}/results/LTR_Table_Digest_TEsorter_Time_nongene_and_gene.tsv" : ""}
    ${params.analysis_type >= 3 ? "- Nearby genes           : ${params.outdir}/results/${params.prefix}.genes_up_and_down_LTR.tsv" : ""}

    Citation:
    If you use MegaLTR, please cite:
    - MegaLTR: https://doi.org/10.3389/fpls.2023.1237426
    ${params.analysis_type == 4 ? "- PlantLAI: https://doi.org/10.1093/aobpla/plad015" : ""}
    ==============================================================
    """
}

// ============================================================================
// ERROR HANDLER
// ============================================================================

workflow.onError {
    log.error """
    ==============================================================
    MegaLTR Pipeline Failed
    ==============================================================
    Error message: ${workflow.errorMessage}
    Error report : ${workflow.errorReport}

    Work directory: ${workflow.workDir}

    Troubleshooting:
    1. Check the work directory for failed task logs
    2. Use -resume to restart from last successful checkpoint
    3. Verify input files exist and are valid
    4. Check conda environment is activated
    ==============================================================
    """
}
