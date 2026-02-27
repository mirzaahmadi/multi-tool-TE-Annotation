#!/bin/bash

# This script will download all the necessary data files and containers for the pipeline
# To run: ./setup.sh

set -euo pipefail

# Load all dependencies

# PFAM
# Create main directory
mkdir -p Databases
cd Databases

# Download Pfam database files
wget http://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.dat.gz
wget http://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/Pfam-A.hmm.gz

# Create pfamdb and unpack
mkdir -p pfamdb

gunzip -c Pfam-A.hmm.dat.gz > pfamdb/Pfam-A.hmm.dat
gunzip -c Pfam-A.hmm.gz > pfamdb/Pfam-A.hmm

# Remove compressed files
rm Pfam-A.hmm.gz Pfam-A.hmm.dat.gz

# Clone pfam_scan
git clone https://github.com/aziele/pfam_scan

echo "Pfam database and pfam_scan successfully installed in Databases/"
cd ..


# Training Dataset and Sif Files from Zenodo
# Download TRAINING DATASET
wget https://zenodo.org/records/18777048/files/training_dataset.CSV?download=1

# Download TE Sif Files
mkdir -p TE_pipeline_sif_files
wget -O TE_pipeline_sif_files/annosine_v2.sif $base_url/annosine_v2.sif?download=1
wget -O TE_pipeline_sif_files/earlgrey_v5.1.sif $base_url/earlgrey_v5.1.sif?download=1
wget -O TE_pipeline_sif_files/heliano.sif $base_url/heliano.sif?download=1
wget -O TE_pipeline_sif_files/HiTE_V3.3.3.sif $base_url/HiTE_V3.3.3.sif?download=1







