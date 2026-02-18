# Placeholder Title
Placeholder is a transposable element detetion pipeline which leverages five leading and pre-established TE tools combined with Ai classification to comprehensivly detect the TEs within any input genome. 
This tool is split into three parts - 1. The TE detection portion only using the classic TE detection tools, 2. then one that allows you to train an AI model, 3. and a last one that allows you to actually use that model to help classify unkonwns from step 1. Full process is shown below.

![Pipeline Overview](Pipeline_Overview.png)

# Prerequisites (Do I list every single module on compute canada loaded and python/R library needed - what if I install them in the code? I think I can just put the modules on compute canada because they may be using a different platform and not just load these - for the python and r libraries - as long as they have python whatever installed my scripts which include importing external libraries are good enough)
- StdEnv/2020
- gcc/13.3
- Apptainer
- cd-hit/4.8.1
- python/3.11
- R/4.3.1
- emboss 6.6.0
- hmmer
- Put into container later (Python: sys, subprocess, collections, re, pandas, SeqIO from Biopython, numpy, os, Shutil, argparse, pathlib, random, csv, sklearn, joblib, imabalnced-learn, matplotlib, statistics, seaborn) | (R: stringr, dplyr, knitr, openxlsx, ftrCool)

# Installation using Apptainer or Singularity
- So here I need to think about if someone else is using this thing, how would I translate this so that someone can like 'earlgrey-build' this shit
- This is where I put my docker iamage I guess

# Important Considerations
- For step 2 and 3, This is an experiemental phase using AI classification approaches. the training database that allows you to train a model has been curated from several gold-standard TE databases online. Please take into account that when trained on this dataset, the supervised machine learning Random Forest model is imabalanced. We recommend that if you train the model using our dataset, you take into account the accuracy and how it performs at reliable TE classification for differnet TE classes. We do not say this dataset is good enough, this is mainly an epxloraty aproahc - we recommend that you swap out or enhance this dataset of gold standard TEs with your own database in the same format, and then continue training.
  
# Usage
## Step 1
- Give like the usage of the command line argument for this
### Arguments

### Example outputs from this part


## Step 2
- Give the command for this
### Arguments

### Example outputs from this part


## Step 3
- Give the command for this
### Arguments

### Examples outputs from this part



