#!/bin/bash

source activate wgs1

# view ref
seqkit stat data/wgs/ncbi_pacbio_TL110.fasta

# fastqc
mkdir -p fastqc/illumina fastqc/ont_r10
fastqc data/wgs/NXT20x_R*.fastq.gz -o ./fastqc/illumina
fastqc data/wgs/ont_r10_20x.fastq.gz -o ./fastqc/ont_r10

# illumina
mkdir illumina
# trimmomatic
trimmomatic PE -threads 4 -phred33 data/wgs/NXT20x_R1.fastq.gz data/wgs/NXT20x_R2.fastq.gz illumina/NXT20x_R1_paired.fastq.gz illumina/NXT20x_R1_unpaired.fastq.gz illumina/NXT20x_R2_paired.fastq.gz illumina/NXT20x_R2_unpaired.fastq.gz ILLUMINACLIP:data/wgs/NexteraPE-PE.fa:2:30:10 LEADING:3 TRAILING:3 MINLEN:50
# bbmap
# clumpify dedupe
#https://www.biostars.org/p/225338/
clumpify.sh in=illumina/NXT20x_R1_paired.fastq.gz in2=illumina/NXT20x_R2_paired.fastq.gz out=illumina/NXT20x_R1_paired_dedup.fastq.gz out2=illumina/NXT20x_R2_paired_dedup.fastq.gz dedupe optical spany adjacent
# bbduk
bbduk.sh in=illumina/NXT20x_R1_paired_dedup.fastq.gz in2=illumina/NXT20x_R2_paired_dedup.fastq.gz out=illumina/NXT20x_R1_paired_dedup_deduk.fastq.gz out2=illumina/NXT20x_R2_paired_dedup_deduk.fastq.gz ref=data/wgs/phiX174.fasta k=31 hdist=1
# spades
spades.py --isolate -t 4 -1 illumina/NXT20x_R1_paired_dedup_deduk.fastq.gz -2 illumina/NXT20x_R2_paired_dedup_deduk.fastq.gz -o illumina/spades

# nanopore
mkdir ont_r10
# optional: guppy/porechop trim barcoder
guppy_barcoder -i data/wgs/ont_r10_20x.fastq.gz -s ont_r10/ont_r10_20x_barcoded.fastq.gz --barcode_kits EXP-NBD104 --trim_barcodes
porechop -i data/wgs/ont_r10_20x.fastq.gz -o ont_r10/ont_r10_20x_porechop.fastq.gz --threads 4
# seqkit
seqkit seq -j 4 -Q 10 -m 2000 -i data/wgs/ont_r10_20x.fastq.gz -o ont_r10/ont_r10_20x_f.fastq.gz
# flye
flye --nano-raw ont_r10/ont_r10_20x_f.fastq.gz --out-dir ont_r10/flye --threads 4
# raon medaka
medaka tools list_models
medaka_consensus -i ont_r10/ont_r10_20x_f.fastq.gz -d ont_r10/flye/assembly.fasta -o ont_r10/medaka -t 4 -m r1041_e82_260bps_hac_v4.1.0

mkdir ont_r10/racon
minimap2 -t 4 -x map-ont ont_r10/flye/assembly.fasta ont_r10/ont_r10_20x_f.fastq.gz > ont_r10/racon/flye_assembly.paf
racon -t 4 ont_r10/ont_r10_20x_f.fastq.gz ont_r10/racon/flye_assembly.paf ont_r10/flye/assembly.fasta > ont_r10/racon/racon.fasta
medaka_consensus -i ont_r10/ont_r10_20x_f.fastq.gz -d ont_r10/racon/racon.fasta -o ont_r10/racon/medaka -t 4 -m r1041_e82_260bps_hac_v4.1.0

# hybrid
# pilon
mkdir -p hybrid/pilon
bwa index ont_r10/medaka/consensus.fasta
bwa mem -t 4 ont_r10/medaka/consensus.fasta illumina/NXT20x_R1_paired_dedup_deduk.fastq.gz illumina/NXT20x_R2_paired_dedup_deduk.fastq.gz | samtools sort -@ 4 -o hybrid/pilon/aligned.bam
samtools index hybrid/pilon/aligned.bam
pilon --genome ont_r10/medaka/consensus.fasta --frags hybrid/pilon/aligned.bam --output hybrid/pilon/pilon --threads 4

# unicycler
unicycler -l ont_r10/ont_r10_20x_f.fastq.gz -1 illumina/NXT20x_R1_paired_dedup_deduk.fastq.gz -2 illumina/NXT20x_R2_paired_dedup_deduk.fastq.gz -o hybrid/unicycler --threads 4

# quast
seqkit stat data/wgs/assemblies/*.fasta
quast data/wgs/assemblies/*.fasta -r data/wgs/ncbi_pacbio_TL110.fasta -o quast

# prokka
mkdir proovframe
source activate wgs2
prokka --outdir proovframe/prokka --prefix pacbio --cpus 4 data/wgs/ncbi_pacbio_TL110.fasta
# proovframe
proovframe map -a proovframe/prokka/pacbio.faa -o proovframe/pilon.tsv hybrid/pilon/pilon.fasta
proovframe fix -o proovframe/pilon_corrected.fasta hybrid/pilon/pilon.fasta proovframe/pilon.tsv