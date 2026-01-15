#!/usr/bin/env nextflow

/*
 * MegaLTR Nextflow Pipeline
 * Phase 6: Bash to Nextflow Migration
 *
 * Author: Asmaa Boulhend
 * Date: 2026-01-13
 */

nextflow.enable.dsl=2

// Pipeline parameters
params.genome = null
params.gff = null
params.outdir = "megaltr_results"
params.threads = 4
params.help = false

// Help message
def helpMessage() {
    log.info"""
    ==============================================================
    MegaLTR Nextflow Pipeline v2.0
    ==============================================================

    Usage:
      nextflow run main.nf --genome <genome.fna> --gff <annotation.gff>

    Required arguments:
      --genome FILE       Input genome FASTA file
      --gff FILE          Input GFF annotation file

    Optional arguments:
      --outdir DIR        Output directory (default: megaltr_results)
      --threads INT       Number of threads (default: 4)
      --help              Show this help message

    Example:
      nextflow run main.nf \\
        --genome Data_for_test/NC_003070.9_Arabidopsis_thaliana.fna \\
        --gff Data_for_test/Arabidopsis_thaliana.gff \\
        --threads 4

    ==============================================================
    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

// Validate required parameters
if (!params.genome) {
    log.error "ERROR: --genome parameter is required"
    helpMessage()
    exit 1
}

if (!params.gff) {
    log.error "ERROR: --gff parameter is required"
    helpMessage()
    exit 1
}

// Print parameter values
log.info """
==============================================================
MegaLTR Nextflow Pipeline - Starting
==============================================================
Genome   : ${params.genome}
GFF      : ${params.gff}
Output   : ${params.outdir}
Threads  : ${params.threads}
==============================================================
"""

/*
 * PROCESS: Prepare genome and annotation files
 */
process PREPARE_GENOME {
    tag "Preparing input files"
    publishDir "${params.outdir}/prepared", mode: 'copy'

    input:
    path genome
    path gff

    output:
    path "genome_prepared.fna", emit: genome
    path "annotation.gff", emit: gff
    path "mapping.txt", emit: mapping

    script:
    """
    # Replace IDs in genome (Python script from Phase 3)
    python3 ${projectDir}/bin/RUN/replaceIDs.py \\
        ${genome} '>\\S+' mapping.txt

    mv ${genome} genome_prepared.fna
    cp ${gff} annotation.gff

    echo "Genome preparation complete"
    """
}

/*
 * PROCESS: Run LTR_FINDER
 */
process LTR_FINDER {
    tag "LTR_FINDER detection"
    publishDir "${params.outdir}/ltr_finder", mode: 'copy'

    cpus params.threads

    input:
    path genome

    output:
    path "genome.finder.combine.scn", emit: scn

    script:
    """
    # Run LTR_FINDER
    ${projectDir}/bin/LTR_FINDER_parallel/LTR_FINDER_parallel \\
        -seq ${genome} \\
        -threads ${task.cpus} \\
        -harvest_out \\
        -size 1000000 \\
        -time 300

    echo "LTR_FINDER complete"
    """
}

/*
 * PROCESS: Run LTR_HARVEST
 */
process LTR_HARVEST {
    tag "LTR_HARVEST detection"
    publishDir "${params.outdir}/ltr_harvest", mode: 'copy'

    cpus params.threads

    input:
    path genome

    output:
    path "genome.harvest.combine.scn", emit: scn

    script:
    """
    # Run LTR_HARVEST_parallel
    perl ${projectDir}/bin/LTR_HARVEST_parallel/LTR_HARVEST_parallel \\
        -seq ${genome} \\
        -threads ${task.cpus} \\
        -size 5000000 \\
        -time 300 \\
        -try1 1 \\
        -cut ${projectDir}/bin/LTR_HARVEST_parallel/bin/cut.pl \\
        -gt ${projectDir}/bin/genometools-1.5.9/bin/gt

    echo "LTR_HARVEST complete"
    """
}

/*
 * WORKFLOW: Main pipeline workflow
 */
workflow {
    // Create channels from input files
    genome_ch = Channel.fromPath(params.genome, checkIfExists: true)
    gff_ch = Channel.fromPath(params.gff, checkIfExists: true)

    // Step 1: Prepare genome
    PREPARE_GENOME(genome_ch, gff_ch)

    // Step 2: Run LTR detection in parallel
    LTR_FINDER(PREPARE_GENOME.out.genome)
    LTR_HARVEST(PREPARE_GENOME.out.genome)

    // TODO: Add more processes
    // - Merge LTR detection results
    // - Run LTR_retriever
    // - Extract sequences
    // - Cluster and classify
    // - Generate final reports
}

/*
 * Workflow completion
 */
workflow.onComplete {
    log.info """
    ==============================================================
    MegaLTR Pipeline Complete!
    ==============================================================
    Status   : ${workflow.success ? 'SUCCESS' : 'FAILED'}
    Duration : ${workflow.duration}
    Output   : ${params.outdir}
    ==============================================================
    """
}
