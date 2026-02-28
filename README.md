TE Atlas
TE Atlas is a transposable element detetion pipeline which leverages five leading and pre-established TE tools combined with AI classification to comprehensivly detect the TEs within any input genome. 
This tool is split into three parts - 1. The TE detection portion only using the classic TE detection tools, 2. then one that allows you to train an AI model, 3. and a last one that allows you to actually use that model to help classify unkonwns from step 1. Full process is shown below. The general framework is illustrated below:

![Pipeline Overview](Examples/Pipeline_Overview.png)

## Video demo link for how it works
https://youtu.be/iEsX8fwtbNY 

## Set up 
1. Git clone this repository (make this git clone thing proper I want it as markdown) in a HPC cluster environment
2. Then run the .setup/ file which sets up all databases and container files ensuring that you have everything you need to begin.


# Prerequisites 
- StdEnv/2020
- gcc/13.3
- Apptainer
- cd-hit/4.8.1
- python/3.11
- R/4.3.1
- emboss 6.6.0
- hmmer


# Important Considerations
- Note that the way the scripts are written and shit, this will only work in the way that I set it up if you are on a compute canada. it used like module load ... and stuff which is ocmpute canada sepcific, so for now, only HPC systems on Compute Canada are supported
- For step 2 and 3, This is an experiemental phase using AI classification approaches. the training database that allows you to train a model has been curated from several gold-standard TE databases online. Please take into account that when trained on this dataset, the supervised machine learning Random Forest model is imabalanced. We recommend that if you train the model using our dataset, you take into account the accuracy and how it performs at reliable TE classification for differnet TE classes. We do not say this dataset is good enough, this is mainly an epxloraty aproahc - we recommend that you swap out or enhance this dataset of gold standard TEs with your own database in the same format, and then continue training.
- Please ensure that the gneome headers you put in are of standard genome conventional formats conventional with GenBank and NCBI: like this strcuture Structure: Accession ID, organism name, chromosome scaffold info, and then assembly info, otherwise some tools may not accept certain formats, so just reworrk your genome headers if need be to fit this requirement. eg. of a good one is this: KZ451882.1 Felis catus isolate Cinnamon breed Abyssinian unplaced genomic scaffold chrUn_Scaffold_147, whole genome shotgun sequence.


# Usage

## Step 1
Given an input genome, the first step of this pipeline will run it through numerous tools to detect and classify TEs.

```bash
# Run with minimum command options
sbatch main.sh -- -g [genome.fna/fasta]
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

Directories created by this step:

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

### Example output table for Salmon Louse Genome - "COMPLETE_TE_RESULTS_<genome_name>.csv"

| cluster   | length (nt) | Pipeline Used | Sequence Information | location | similarity (%) | Representative Sequence? | Pipeline_Count | Unknown_Status | family_count | Proteins |
|------------|------------|--------------|----------------------|----------|----------------|--------------------------|----------------|----------------|--------------|----------|
| Cluster 5 | 76   | EARLGREY | rnd-5_family-6073#Unknown_(Recon_Family_Size_=28, Final_Multiple_Alignment_Size_=28) | at 73:7:4348:4413/- | 86.57% | No  |  |  |  |  |
| Cluster 5 | 7005 | HELIANO | insertion_Helitron_nonauto_11 | * |  | YES | EARLGREY: 2, HELIANO: 1 | UNKNOWN PRESENT: Discovered | non_autonomous_helitron: 1 |  |
| Cluster 6 | 6632 | HELIANO | insertion_Helitron_nonauto_22 | * |  | YES | HELIANO: 1 |  | non_autonomous_helitron: 1 |  |
| Cluster 7 | 6237 | EARLGREY | rnd-1_family-40#Unknown_(RepeatScout_Family_Size_=393, Final_Multiple_Alignment_Size_=100, Localized_to_377_out_of_491_contigs_) | * |  | YES | EARLGREY: 1 | UNKNOWN PRESENT: Undiscovered |  | Astacin |
| Cluster 8 | 5973 | EARLGREY | rnd-4_family-812#DNA/hAT-Tag1_(Recon_Family_Size_=38, Final_Multiple_Alignment_Size_=35) | * |  | YES | EARLGREY: 1 |  | DNA/hAT-Tag1: 1 |  |
| Cluster 9 | 1110 | EARLGREY | rnd-4_family-205#LINE/L1_(Recon_Family_Size_=80, Final_Multiple_Alignment_Size_=67) | at 1:1110:4526:5634/+ | 87.99% | No |  |  |  |  |


## Step 2
The second step of this pipeline involves training a machine learning model off of a dataset of gold-standard TEs - this database can be substituted for yoru dataset if you have one.

### Example of the training dataset that was used in my tests - any table that you put in place of this should have the same format and same column names

| Sequence_ID | sequence_content | TE_Order |
|-------------|-----------------|----------|
| DF0000004 | CAGTCATGCGCCGCATAACGACGTTT... | TIR |
| DF0000005 | TGATATGGTTTGGCTGTGTCCCCACC... | LTR |
| DF0000006 | TCTATCTATATAAAATGCTTAGGTAT... | Helitron |
| DF0000007 | GGCCGGGCGCGGTGGCTCACGCCTGT... | SINE |
| DF0000008 | ATGGTAGATTTAAACCCAANCATATC... | Non-LTR/LINE |

```bash
# Run with minimum command options
sbatch Train_Model.sh <dataset.csv>
```

```text
# Required Parameters:
<dataset.csv> == Labelled TE dataset which will be used to train the model

# Optional Parameters:
--kbest <int> == specifies how many of the most relevant features  to keep when using SelectKBest from scikit-learn.
--n-estimators <int> == It sets how many decision trees are built during training.
```

Directories created by this step:

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

### Example output - the EDA sequence length boxplot for one TE order and the per-class metrics from the training_dataset supervised machine learning model
![Sequence_Length_Boxplot](Examples/Non-LTR_LINE_Seq_Length_Boxplot.png) 
![Training_Metrics](Examples/per_class_metrics.png)

## Step 3
Use the trained machine learning model to classify any remaining unknown sequences 

```bash
# Run with minimum command options
sbatch classify.sh <complete_csv> <cdhit_output> <model_pkl> <scaler_pkl> <label_encoder_pkl> <selector_pkl> 
```

```text
# Required Parameters:
<complete_csv> == Complete TE results table (outputted from step 1)
<cdhit_output> == CD-HIT consensus sequence FASTA (outputted from step 1)
<model_pkl> == Serialized trained random forest model (outputted from step 2)
<scaler_pkl> == Serialized scaler (outputted from step 2)
<label_encoder_pkl> == Serialized label encoder (outputted from step 2)
<selector_pkl> == Serialized feature selector (outputted from step 2)

# Optional Parameters:
--classifier-threshold <float> == Specifies AI model confidence threshold for TE classification – default value of 0.70 is used if not specified
```

Directories created by this step:

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

### Example output  - a classification summary of all the unkonwns that are now reclassified or whatever
![Training_Metrics](Examples/classification_summary_threshold_0.70.png)


# References 
Baril, T., Galbraith, J.G., and Hayward, A., Earl Grey: A Fully Automated User-Friendly Transposable Element Annotation and Analysis Pipeline, Molecular Biology and Evolution, Volume 41, Issue 4, April 2024, msae068 doi:10.1093/molbev/msae068

Hu, K., Ni, P., Xu, M. et al. HiTE: a fast and accurate dynamic boundary adjustment approach for full-length transposable element detection and annotation. Nat Commun 15, 5573 (2024). https://doi.org/10.1038/s41467-024-49912-8

Yang Li, Ning Jiang, Yanni Sun, AnnoSINE: a short interspersed nuclear elements annotation tool for plant genomes, Plant Physiology, Volume 188, Issue 2, February 2022, Pages 955–970, https://doi.org/10.1093/plphys/kiab524

Li Z , Gilbert C , Peng H , Pollet N. "Discovery of numerous novel Helitron-like elements in eukaryote genomes using HELIANO." Nucleic Acids Research, 2024. doi: doi.org/10.1093/nar/gkae679.

Li Z , Pollet N. "HELIANO: a Helitron-like element annotator." Zenodo (2024). doi: 10.5281/zenodo.10625239

Hu J, Zheng Y, Shang X. MiteFinderII: a novel tool to identify miniature inverted-repeat transposable elements hidden in eukaryotic genomes. BMC medical genomics. 2018 Nov;11(5):51-9. https://doi.org/10.1186/s12920-018-0418-y

Weizhong Li, Adam Godzik, Cd-hit: a fast program for clustering and comparing large sets of protein or nucleotide sequences, Bioinformatics, Volume 22, Issue 13, July 2006, Pages 1658–1659, https://doi.org/10.1093/bioinformatics/btl158

Zielenkiewicz, P. (n.d.). pfam_scan (Version X.X) [Computer software]. GitHub. https://github.com/aziele/pfam_scan

# Acknowledgements

This work has been my masters thesis project in Bioinformatics and Artificial Intelligence at the university of Guelph. This work would not have been possible without the support and guidance of my master's thesis committee: Dr. T. Ryan Gregory, Dr. Stefan Kremer, Dr. Tyler Elliott and Dr. Brent Saylor.

