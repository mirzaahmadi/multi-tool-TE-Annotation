# TE Atlas
**TE Atlas** is an integrated transposable element (TE) detection and classification pipeline that leverages five established TE annotation tools combined with supervised machine learning to comprehensively detect and characterize TEs within any input genome.

# Contents
- [Overview](#overview)
- [Setup](#setup)
- [Prerequisites](#prerequisites)
- [Important Considerations](#important-considerations)
- [Usage](#usage)
- [References](#references)
- [Acknowledgements](#acknowledgements)


# Overview
The pipeline consists of three modular components:
1. **Multi-tool TE detection** using established annotation tools  
2. **Supervised machine learning model training**  
3. **AI-based classification** of remaining unknown sequences  

The overall workflow is illustrated below:
![Pipeline Overview](Examples/Pipeline_Overview.png)

## Video Demonstration
A full walkthrough of TE Atlas is available <a href="https://youtu.be/iEsX8fwtbNY" target="_blank">
   here
</a>

---

# Setup
### 1️. Clone the Repository
Run the following in a supported HPC cluster environment:
```bash
git clone https://github.com/mirzaahmadi/TE-Atlas.git
cd TE-Atlas
```

### 2. Run the Setup Script
Execute the setup script to download required databases and container files:
```bash
# If need be: chmod +x setup.sh
./setup.sh
```
This ensures all required resources are configured before running the pipeline.

---

# Prerequisites
TE Atlas is currently configured for the **Digital Research Alliance of Canada (Compute Canada)** HPC environment. The following modules must be available:
- StdEnv/2020  
- gcc/13.3  
- Apptainer  
- cd-hit/4.8.1  
- python/3.11  
- R/4.3.1  
- emboss/6.6.0  
- hmmer  

---

# Important Considerations

### Platform Compatibility
The current implementation of TE Atlas is configured specifically for the Digital Research Alliance of Canada (Compute Canada) HPC environment. The scripts rely on `module load` commands and other environment-specific configurations that are particular to Alliance systems. As a result, the pipeline will only function as intended on Compute Canada HPC clusters. Portability to other HPC systems or local environments is not currently supported.

### Machine Learning Component and Training Dataset
Steps 2 and 3 introduce an experimental supervised machine learning component for TE classification. The provided training dataset was curated from multiple gold-standard TE databases; however, it is class-imbalanced, and model performance may vary across TE orders. Users should carefully evaluate classification accuracy and per-class performance when training on the default dataset. This dataset is intended as an exploratory starting point rather than a definitive solution. For optimal results, users are strongly encouraged to replace or augment the provided dataset with their own curated TE database in the same format before retraining the model.

### Genome FASTA Header Requirements
Input genome FASTA headers must follow conventional GenBank/NCBI-style formatting, including an accession ID, organism name, chromosome or scaffold identifier, and assembly information. Certain annotation tools may fail if non-standard header formats are used. Users should ensure that genome headers are properly formatted prior to running the pipeline.

Example of an appropriate header format: 
```bash
>KZ451882.1 Felis catus isolate Cinnamon breed Abyssinian unplaced genomic scaffold chrUn_Scaffold_147, whole genome shotgun sequence
```
Improper header formatting may cause certain tools to fail. Adjust headers as needed before running the pipeline.

---

# Usage

> ⚠️ **Resource Allocation Notice**  
> Before running each pipeline step, review and adjust the CPU cores, memory, time limits, and temporary storage settings specified in the `#SBATCH` directives at the top of the corresponding Bash script.  
> These values should be tailored to your genome size, dataset scale, and HPC allocation to ensure efficient and successful execution.

## Step 1 — Multi-tool annotation
Given an input genome, this step runs multiple integrated tools to detect and classify TEs.

```bash
# Run with minimum command options
sbatch 1_main.sh -- -g [genome.fna/fasta]
```

```text
# Required Parameters:
-g == genome.fasta

# Optional Parameters:
-t == Keep all tools' intermediate output files
-e == Keep Earl Grey genome support files
-f == Keep prefixed fasta output files
-c == Keep CD-HIT output files
-p == Keep pfam_scan intermediate output files
--reference_library <library.fasta> == Use custom consensus library
--plant == Indicates genome is a plant (HiTE specific)
```

### Output Directory Structure

```text
<genome_name>_outputs/
    ├── COMBINED_TE_SEQUENCES_<genome_name>.fa
    ├── COMPLETE_TE_RESULTS_<genome_name>.csv
    ├── FINAL_cdhit_<genome_name>
    ├── pfam_output_<genome_name>.csv
    ├── TE_FASTAs_from_TE_Pipelines/
    │   ├── Prefixed_<genome_name>-families.fa
    │   ├── Prefixed_<genome_name>_<hash>-matches.FASTA
    │   ├── Prefixed_RC.representative.fa
    │   ├── Prefixed_confident_TE.cons.fa
    │   └── prefixed_mitefinder_file
    ├── TE_pipeline_intermediate_outputs/
    │   ├── <genome_name>_ANNOSINE_outputs
    │   ├── <genome_name>_HELIANO_outputs
    │   ├── <genome_name>_HITE_outputs
    │   └── earlGreyOutputs
    │   └── mitefinder_outputs
    ├── cd-hit_round_1_outputs/
    │   ├── Clustered_COMBINED_TE_SEQUENCES_<genome_name>
    │   └── Clustered_COMBINED_TE_SEQUENCES_<genome_name>.clstr
    ├── cd-hit_round_2_outputs/
    │   ├── FINAL_cdhit_<genome_name>.clstr
    │   └── FINAL_cdhit_<genome_name>_PROTOTYPE.xlsx
    ├── earlgrey_genome_support_files/
    │   └── Genome Preparation files
    └── pfam_intermediate_outputs/
        └── Representative_Sequences_<genome_name>.FASTA
```

### Example output

<figure>
  <figcaption><strong>COMPLETE_TE_RESULTS_&lt;genome_name&gt;.csv</strong></figcaption>

| cluster   | length (nt) | Pipeline Used | Sequence Information | location | similarity (%) | Representative Sequence? | Pipeline_Count | Unknown_Status | family_count | Proteins |
|------------|------------|--------------|----------------------|----------|----------------|--------------------------|----------------|----------------|--------------|----------|
| Cluster 5 | 76   | EARLGREY | rnd-5_family-6073#Unknown_(Recon_Family_Size_=28, Final_Multiple_Alignment_Size_=28) | at 73:7:4348:4413/- | 86.57% | No  |  |  |  |  |
| Cluster 5 | 7005 | HELIANO | insertion_Helitron_nonauto_11 | * |  | YES | EARLGREY: 2, HELIANO: 1 | UNKNOWN PRESENT: Discovered | non_autonomous_helitron: 1 |  |
| Cluster 6 | 6632 | HELIANO | insertion_Helitron_nonauto_22 | * |  | YES | HELIANO: 1 |  | non_autonomous_helitron: 1 |  |
| Cluster 7 | 6237 | EARLGREY | rnd-1_family-40#Unknown_(RepeatScout_Family_Size_=393, Final_Multiple_Alignment_Size_=100, Localized_to_377_out_of_491_contigs_) | * |  | YES | EARLGREY: 1 | UNKNOWN PRESENT: Undiscovered |  | Astacin |
| Cluster 8 | 5973 | EARLGREY | rnd-4_family-812#DNA/hAT-Tag1_(Recon_Family_Size_=38, Final_Multiple_Alignment_Size_=35) | * |  | YES | EARLGREY: 1 |  | DNA/hAT-Tag1: 1 |  |
| Cluster 9 | 1110 | EARLGREY | rnd-4_family-205#LINE/L1_(Recon_Family_Size_=80, Final_Multiple_Alignment_Size_=67) | at 1:1110:4526:5634/+ | 87.99% | No |  |  |  |  |

</figure>


## Step 2 — Train the Machine Learning Model
Train a Random Forest classifier using a labelled TE dataset.

```bash
# Run with minimum command options
sbatch 2_train_model.sh <dataset.csv>
```

```text
# Required Parameters:
<dataset.csv> == Labelled TE dataset used to train the supervised machine learning model

# Optional Parameters:
--kbest <int> == Specifies number of top features to retain using SelectKBest (feature selection)
--n-estimators <int> == Specifies number of decision trees to build in the Random Forest model
```

This dataset may be replaced with your own labelled TE database, provided it follows this same structure and column format to ensure compatability with the training workflow:

| Sequence_ID | sequence_content | TE_Order |
|-------------|-----------------|----------|
| DF0000004 | CAGTCATGCGCCGCATAACGACGTTT... | TIR |
| DF0000005 | TGATATGGTTTGGCTGTGTCCCCACC... | LTR |
| DF0000006 | TCTATCTATATAAAATGCTTAGGTAT... | Helitron |
| DF0000007 | GGCCGGGCGCGGTGGCTCACGCCTGT... | SINE |
| DF0000008 | ATGGTAGATTTAAACCCAANCATATC... | Non-LTR/LINE |

### Output Directory Structure

```text
Training_outputs-<training_dataset_name>/
    ├── [output_log].out
    └── Training_Outputs-<training_dataset_name>/
        ├── Intermediate_dataset_files/
        │   ├── PREPROCESSED_training_dataset.csv
        │   └── FINAL_training_dataset.csv
        ├── Model_Artifacts/
        │   ├── FEATURE_SELECTOR_<training_dataset_name>.pkl
        │   ├── LABEL_ENCODER__<training_dataset_name>.pkl
        │   ├── SCALER__<training_dataset_name>.pkl
        │   └── TRAINED_MODEL__<training_dataset_name>.pkl
        ├── Visualizations/
        │   ├── Ambiguous_nucleotides_plot.png
        │   ├── Training Metrics/
        │   │   ├── classification_report.csv
        │   │   ├── confusion_matrix.png
        │   │   └── per_class_metrics.png
        │   └── Seq_Len_Plots_After_Preprocessing/
        │       ├── Crypton_Seq_Length_Boxplot.png
        │       ├── DIRS_Seq_Length_Boxplot.png
        │       ├── Helitron_Seq_Length_Boxplot.png
        │       ├── LTR_Seq_Length_Boxplot.png
        │       ├── Maverick_Seq_Length_Boxplot.png
        │       ├── Non-LTR_LINE_Seq_Length_Boxplot.png
        │       ├── PLE_Seq_Length_Boxplot.png
        │       ├── SINE_Seq_Length_Boxplot.png
        │       └── TIR_Seq_Length_Boxplot.png
```

Example outputs:
<figure>
  <img src="Examples/Non-LTR_LINE_Seq_Length_Boxplot.png" width="600">
  <figcaption><em>Sequence length distribution for Non-LTR/LINE elements.</em></figcaption>
</figure>


<figure>
  <img src="Examples/per_class_metrics.png" width="600">
  <figcaption><em>Per-class performance metrics from the trained model.</em></figcaption>
</figure>


## Step 3 — Classify Remaining Unknown Sequences

Use the trained model to classify remaining unknown sequences from Step 1.

```bash
# Run with minimum command options
sbatch 3_classify.sh <complete_csv> <cdhit_output> <model_pkl> <scaler_pkl> <label_encoder_pkl> <selector_pkl> 
```

```text
# Required Parameters:
<complete_csv> == Complete TE results table (outputted from step 1 as "COMPLETE_TE_RESULTS_[genome].fa/fna")
<cdhit_output> == CD-HIT consensus sequence FASTA (outputted from step 1 as "FINAL_cdhit_[genome]")
<model_pkl> == Serialized trained random forest model (outputted from step 2)
<scaler_pkl> == Serialized scaler (outputted from step 2)
<label_encoder_pkl> == Serialized label encoder (outputted from step 2)
<selector_pkl> == Serialized feature selector (outputted from step 2)

# Optional Parameters:
--classifier-threshold <float> == Specifies AI model confidence threshold for TE classification – default value of 0.70 is used if not specified
```


### Output Directory Structure
```text
Classification_outputs/
    ├── [output_log].out
    └── classification_outputs/
        ├── Classification_Results/
        │   ├── classification_results.csv
        │   └── classification_summary.png
        └── Intermediate_dataset_files/
            ├── original_inference_dataset.csv
            ├── preprocessed_inference_dataset.csv
            ├── feature-extracted_inference_dataset.csv
            └── Final_inference_dataset.csv
```

Example output:
<figure>
  <img src="Examples/classification_summary_threshold_0.70.png" width="700">
  <figcaption><em>Classification summary showing reclassification of previously unknown sequences using the trained model (confidence threshold = 0.70).</em></figcaption>
</figure>

---

# References

Baril, T., Galbraith, J.G., & Hayward, A. (2024). Earl Grey: A fully automated user-friendly transposable element annotation and analysis pipeline. *Molecular Biology and Evolution*, 41(4), msae068. https://doi.org/10.1093/molbev/msae068

Hu, K., Ni, P., Xu, M., et al. (2024). HiTE: a fast and accurate dynamic boundary adjustment approach for full-length transposable element detection and annotation. *Nature Communications*, 15, 5573. https://doi.org/10.1038/s41467-024-49912-8

Li, Y., Jiang, N., & Sun, Y. (2022). AnnoSINE: a short interspersed nuclear elements annotation tool for plant genomes. *Plant Physiology*, 188(2), 955–970. https://doi.org/10.1093/plphys/kiab524

Li, Z., Gilbert, C., Peng, H., & Pollet, N. (2024). Discovery of numerous novel Helitron-like elements in eukaryote genomes using HELIANO. *Nucleic Acids Research*. https://doi.org/10.1093/nar/gkae679

Li, Z., & Pollet, N. (2024). HELIANO: a Helitron-like element annotator. Zenodo. https://doi.org/10.5281/zenodo.10625239

Hu, J., Zheng, Y., & Shang, X. (2018). MiteFinderII: a novel tool to identify miniature inverted-repeat transposable elements hidden in eukaryotic genomes. *BMC Medical Genomics*, 11(S5), 51–59. https://doi.org/10.1186/s12920-018-0418-y

Li, W., & Godzik, A. (2006). Cd-hit: a fast program for clustering and comparing large sets of protein or nucleotide sequences. *Bioinformatics*, 22(13), 1658–1659. https://doi.org/10.1093/bioinformatics/btl158

Zielenkiewicz, P. (n.d.). pfam_scan [Computer software]. GitHub. https://github.com/aziele/pfam_scan

---

# Acknowledgements

This work was developed as part of an MSc thesis in Bioinformatics and Artificial Intelligence at the University of Guelph.

This project would not have been possible without the support and guidance of my thesis committee:  
Dr. T. Ryan Gregory, Dr. Stefan Kremer, Dr. Tyler Elliott, and Dr. Brent Saylor.
