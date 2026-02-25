#!/bin/bash
#SBATCH -t 3-00:00:00
#SBATCH --mem=116G
#SBATCH -c 24
#SBATCH --mail-user=mahmad15@uoguelph.ca
#SBATCH --mail-type=BEGIN,FAIL,END
#SBATCH --account=def-skremer

# =================THE FOLLOWING BLOCK ENSURES THAT THE THREADING FOR THE DIFFERENT TE TOOLS IS CORRECT AND SENSIBLE=================

# 1) Turn OFF hidden threading everywhere (prevents surprise extra threads)
#    OpenMP/BLAS libraries love to spawn threads; we force them to 1.
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# 2) What did SLURM give us: (NOTE: The '-1' and '0' are fallbacks in case these allocations are not specified)
CPUS=${SLURM_CPUS_PER_TASK:-1}       # number of CPU cores for the job
MEM_RAW=${SLURM_MEM_PER_NODE:-0}     # total RAM for the job, e.g. "356G" or "200000M"

# 3) Convert memory to a plain integer in MB
case "$MEM_RAW" in
  *G) MEM_MB=$(( ${MEM_RAW%G} * 1024 )) ;;  # e.g. 356G -> 364,544 MB
  *M) MEM_MB=${MEM_RAW%M} ;;
  *)  MEM_MB=${MEM_RAW:-0} ;;
esac

# 4) Keep some RAM aside so the OS/filesystem doesn’t choke (about 8 GB) - this reserves memory so that I/O caches aren't starved
SAFETY_MB=8192
USABLE_MB=$(( MEM_MB>SAFETY_MB ? MEM_MB-SAFETY_MB : MEM_MB ))

# 5) Rough RAM per worker at peak (MB). 6000 = ~6 GB.
#    This is a *rule-of-thumb* for heavy TE steps; change to 5000–8000 if you see fit.
PER_WORKER_MB=${PER_WORKER_MB:-6000}

# 6) The ONE threads number we’ll reuse everywhere:
#    - Use half the CPUs (simple and safe),
#    - Also don’t exceed what your RAM can afford,
#    - Cap it at 32 so we don’t spawn silly amounts,
#    - Ensure at least 4 workers so it’s not too slow.
CPU_CAP=$(( CPUS/2 ))
MEM_CAP=$(( USABLE_MB / PER_WORKER_MB ))
JOB_THREADS=$CPU_CAP
(( JOB_THREADS > MEM_CAP )) && JOB_THREADS=$MEM_CAP
(( JOB_THREADS > 32 )) && JOB_THREADS=32
(( JOB_THREADS < 4 ))  && JOB_THREADS=4

echo "Threads for tools: $JOB_THREADS  (CPUS=$CPUS, MEM_MB=$MEM_MB, usable=${USABLE_MB}MB)"
echo ""

# 7) HiTE uses chunking; smaller chunks = lower per-worker RAM.
#    200 MB is safer than the default 400 for large genomes.
HITE_CHUNK_SIZE=${HITE_CHUNK_SIZE:-200}

# 8) cd-hit memory budget (MB). Leave ~2 GB headroom to avoid OOM.
CDHIT_MEM_MB=$(( USABLE_MB>2048 ? USABLE_MB-2048 : USABLE_MB ))
(( CDHIT_MEM_MB < 2048 )) && CDHIT_MEM_MB=2048

# ============================================================================================================================================


# Create an empty variable to store the genome
genome=""

# Initialize binary variables as false. However, if flag is given, corresponding variables will switch to true and certain directories will be moved to home directory
tool_outputs=false
earlgrey_outputs=false
prefixed_file_outputs=false
cd_hit_outputs=false
pfam_outputs=false

# The following two variables will denote whether or not there is a new consensus sequence library used in earlgrey implementation, or if genome=plant for the HiTE command
earlgrey_new_reference_library=""
hite_plant_genome=false



# === Manually handle long flags (before getopts) ===
short_args=() # This holds the args we pass to getopts
i=1
while [[ $i -le $# ]]; do # while i is less than or equal to the number of positional arguments in total
  arg="${!i}"
  case "$arg" in
    # NOTE: This is used to tell the shell to stop interpreting flags as it does normally - everything after "--" gets processed by this script. Therefore, the remaining flags will be treated as we specify in this program.
    --) ;;  # ignore this 'setpoint', this is not to be treated like a flag
    --reference_library)
      next=$((i+1))
      val="${!next}" # this is used to store the argument that comes after a --reference_library
      if [[ -z "$val" || "$val" == --* || "$val" == -* ]]; then #if value after --reference_library is empty or if value is another flag instead of an .fa file, throw error
        echo "Error: --reference_library requires a file path argument." >&2
        echo ""
        echo "Usage: sbatch main.sh -- -g <genome_file.fasta> [optional flags]"
        echo ""
        echo "MANDATORY FLAGS:"
        echo "   -g <genome_file.fasta>  : Input genome file (required)"
        echo ""
        echo "OPTIONAL FLAGS:"
        echo "   -t                      : Keep tools' intermediate output files"
        echo "   -e                      : Keep earlgrey genome support files"
        echo "   -f                      : Keep prefixed fasta output files"
        echo "   -c                      : Keep CD-HIT output files"
        echo "   -p                      : Keep PFAM intermediate output files"
        echo "   --reference_library <file.fa>     : Use custom consensus library (instead of default Dfam)"
        echo "   --plant                           : Indicates genome is a plant (for HiTE) - default is No"
        echo ""
        exit 1
      fi
      earlgrey_new_reference_library="$val"
      i=$((i+1))
      ;;
    --plant) # if --plant argument is present, set the hite_plant_genome to true
      hite_plant_genome=true
      ;;
    --*) # if  double flag is anything other than those specified, throw an error
      echo "Unknown option: $arg" >&2
      echo ""
      echo "Usage: sbatch main.sh -- -g <genome_file.fasta> [optional flags]"
      echo ""
      echo "MANDATORY FLAGS:"
      echo "   -g <genome_file.fasta>  : Input genome file (required)"
      echo ""
      echo "OPTIONAL FLAGS:"
      echo "   -t                      : Keep tools' intermediate output files"
      echo "   -e                      : Keep earlgrey genome support files"
      echo "   -f                      : Keep prefixed fasta output files"
      echo "   -c                      : Keep CD-HIT output files"
      echo "   -p                      : Keep PFAM intermediate output files"
      echo "   --reference_library <file.fa>     : Use custom consensus library (instead of default Dfam)"
      echo "   --plant                           : Indicates genome is a plant (for HiTE)"
      echo ""
      exit 1
      ;;
    *) # If there is any other flags (short flags) add them to the short_args list
      short_args+=("$arg")
      ;;
  esac
  i=$((i+1))
done

# Replaces the current script arguments ($1, $2, ...) with only the cleaned short flags
# This prevents getopts from seeing any long flags (e.g., --plant) that would break it
set -- "${short_args[@]}"

# === Parse short flags ===
while getopts "g:tefcp" opt; do
  case $opt in
    g) genome=$OPTARG ;;
    t) tool_outputs=true ;;
    e) earlgrey_outputs=true ;;
    f) prefixed_file_outputs=true ;;
    c) cd_hit_outputs=true ;;
    p) pfam_outputs=true ;;
    *)
      echo ""
      echo "Usage: sbatch main.sh -- -g <genome_file.fasta> [optional flags]"
      echo ""
      echo "MANDATORY FLAGS:"
      echo "   -g <genome_file.fasta>  : Input genome file (required)"
      echo ""
      echo "OPTIONAL FLAGS:"
      echo "   -t                      : Keep tools' intermediate output files"
      echo "   -e                      : Keep earlgrey genome support files"
      echo "   -f                      : Keep prefixed fasta output files"
      echo "   -c                      : Keep CD-HIT output files"
      echo "   -p                      : Keep PFAM intermediate output files"
      echo "   --reference_library <file.fa>     : Use custom consensus library (instead of default Dfam)"
      echo "   --plant                           : Indicates genome is a plant (for HiTE)"
      echo ""
      exit 1
      ;;
  esac
done

# === Validation checks ===
# If no valid argument is given after the -g flag, throw error
if [[ -z "$genome" ]]; then
  echo ""
  echo "ERROR: Genome file (-g) not specified."
  echo ""
  echo "Usage: sbatch main.sh -- -g <genome_file.fasta> [optional flags]"
  echo ""
  echo "MANDATORY FLAGS:"
  echo "   -g <genome_file.fasta>  : Input genome file (required)"
  echo ""
  echo "OPTIONAL FLAGS:"
  echo "   -t                      : Keep tools' intermediate output files"
  echo "   -e                      : Keep earlgrey genome support files"
  echo "   -f                      : Keep prefixed fasta output files"
  echo "   -c                      : Keep CD-HIT output files"
  echo "   -p                      : Keep PFAM intermediate output files"
  echo "   --reference_library <file.fa>     : Use custom consensus library (instead of default Dfam)"
  echo "   --plant                           : Indicates genome is a plant (for HiTE)"
  echo ""
  exit 1
fi

# Specify the working directory as the current directory
working_directory=$(pwd)



# Now, both genome and working_directory should be set and can be used
echo "Genome file: $genome"
echo "Working directory: $working_directory"

# If the earlgrey_new_reference_library file is provided by the user, then print the file name out
if [[ -n "$earlgrey_new_reference_library" ]]; then
  echo "Provided earlgrey reference library: $earlgrey_new_reference_library"
fi


# Store the base name of the genome from the inputted genome
base_name=${genome%.*}

# Create a directory which will act as the outputs folder for all files and folders from a run
final_outputs_folder="${base_name}_outputs"
mkdir $final_outputs_folder
echo ""
echo "Output Directory created: $final_outputs_folder"
echo ""

#Load apptainer which allows us to run the .sif files that permit the usage of the TE pipelines.
module load apptainer

#Create an intermediate directory within TMPDIR to store all intermediate outputs of earlgrey, HiTE, Annosine, Heliano and Mitefinder
mkdir -p "$TMPDIR/TE_pipeline_intermediate_outputs"


#EARLGREY

start_time_earlgrey=$(date +%s)
echo ""
echo "--------------------STARTING EARLGREY--------------------"
echo ""

#Make SLURM $earlGreyOutputs folder inside of $TMPDIR
mkdir -p "$TMPDIR/TE_pipeline_intermediate_outputs/earlGreyOutputs"

# NOTE: earlgrey_v5.1.sif is the latest version of earlgrey. It is found within TE_pipeline_sif_files, along with other version(s) of earlgrey.

# If a user specified a different reference library for earlgrey, include that within the earlgrey command. Else, run default command.
if [[ -n "$earlgrey_new_reference_library" ]]; then # If there is a specified reference library, incorporate that into the earlgrey command
  earlgrey_new_reference_library=$(realpath "$earlgrey_new_reference_library")
  apptainer run ./TE_pipeline_sif_files/earlgrey_v5.1.sif earlGrey -g $genome -s $base_name -l "$earlgrey_new_reference_library" -t $JOB_THREADS -o "$TMPDIR/TE_pipeline_intermediate_outputs/earlGreyOutputs"
else # If no specified reference library
  apptainer run ./TE_pipeline_sif_files/earlgrey_v5.1.sif earlGrey -g $genome -s $base_name -t $JOB_THREADS -o "$TMPDIR/TE_pipeline_intermediate_outputs/earlGreyOutputs"
fi

# Find the specific file within the output folder that ends with _Database and store its path in a variable
EarlGrey_FamilyFile=$(find "$TMPDIR/TE_pipeline_intermediate_outputs/earlGreyOutputs" -type f -path "*_Database/*" -name "${base_name}-families.fa")

# Simple check to see if the specified file was found
if [ -z "$EarlGrey_FamilyFile" ]; then
  echo "File ${base_name}-families.fa not found."
  exit 1
else
  # Add prefix to the sequences and store the result in a new file in the same directory
  Prefixed_EarlGrey_FamilyFile="Prefixed_${base_name}-families.fa"
  sed -E '/^>/ { s/^>/&EARLGREY_/; s/ /_/g; }' "$EarlGrey_FamilyFile" > "$TMPDIR/TE_pipeline_intermediate_outputs/earlGreyOutputs/$Prefixed_EarlGrey_FamilyFile"

  # Move the new file to the main directory
  mv "$TMPDIR/TE_pipeline_intermediate_outputs/earlGreyOutputs/$Prefixed_EarlGrey_FamilyFile" ./$final_outputs_folder

  # Notify that the file has been moved
  echo "File moved to $final_outputs_folder directory: $Prefixed_EarlGrey_FamilyFile"
fi

end_time_earlgrey=$(date +%s)
elapsed_earlgrey=$((end_time_earlgrey - start_time_earlgrey))

echo ""
echo "--------------------FINISHED EARLGREY | ELAPSED TIME: $((elapsed_earlgrey / 60)) min $((elapsed_earlgrey % 60)) sec--------------------"
echo ""

#HiTE

start_time_HiTE=$(date +%s)
echo ""
echo "--------------------STARTING HiTE--------------------"
echo ""

#Make HITE outputs folder inside of $TMPDIR
mkdir -p "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HITE_outputs"

# If the user inputs the "--plant" argument, then we can specify to HiTE that this is a plant genome
if [[ "$hite_plant_genome" == true ]]; then
  hite_plant_flag=1 # User specified --plant: treat as plant genome
else
  hite_plant_flag=0 # Default or unspecified: treat as non-plant genome
fi

apptainer run -B "$working_directory:$working_directory" --pwd /HiTE \
  "$working_directory/TE_pipeline_sif_files/HiTE_V3.3.3.sif" python main.py \
    --genome "$working_directory/$genome" \
    --thread "$JOB_THREADS" \
    --chunk_size 200 \
    --plant "$hite_plant_flag" \
    --out_dir "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HITE_outputs" \
    --work_dir "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HITE_outputs"


#Find the specific file within the HITE output folder and store its path in a variable
HiTE_TE_File=$(find "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HITE_outputs" -type f -name "confident_TE.cons.fa")

# Simple check to see if the specified file was found
if [ -z "$HiTE_TE_File" ]; then
  echo "File confident_TE.cons.fa not found."
  exit 1
else
  # Extract the base name of the HiTE file without the path - NOTE: The 'basename' command in Bash is used to strip directory and suffix from filenames eg. basename /usr/bin/sort # Output: sort
  HiTE_TE_File_Base=$(basename "$HiTE_TE_File")

  # Add prefix to the sequences and store the result in a new file in the same directory
  Prefixed_HiTE_TE_File="Prefixed_${HiTE_TE_File_Base}"
  sed -E '/^>/ { s/^>/&HITE_/; s/ /_/g; }' "$HiTE_TE_File" > "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HITE_outputs/$Prefixed_HiTE_TE_File"

  # Move the new file to the main directory
  mv "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HITE_outputs/$Prefixed_HiTE_TE_File" ./$final_outputs_folder

  # Notify that the file has been moved
  echo "File moved to $final_outputs_folder directory: $Prefixed_HiTE_TE_File"
fi

end_time_HiTE=$(date +%s)
elapsed_HiTE=$((end_time_HiTE - start_time_HiTE))

echo ""
echo "--------------------FINISHED HiTE | ELAPSED TIME: $((elapsed_HiTE / 60)) min $((elapsed_HiTE % 60)) sec--------------------"
echo ""

#ANNOSINE

start_time_annosine=$(date +%s)
echo ""
echo "--------------------STARTING ANNOSINE--------------------"
echo ""

#Make ANNOSINE outputs folder inside of $TMPDIR
mkdir -p "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_ANNOSINE_outputs"

# NOTE: AnnoSINE_v2 is the latest version of AnnoSINE. It is found within TE_pipeline_sif_files along with other version(s) of AnnoSINE.
apptainer run ./TE_pipeline_sif_files/annosine_v2.sif AnnoSINE_v2 -t $JOB_THREADS 3 $genome "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_ANNOSINE_outputs"

# Find the specific file within the ANNOSINE output folder and store its path in a variable
AnnoSINE_TE_File=$(find "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_ANNOSINE_outputs" -type f -name "*-matches.fasta")

# Simple check to see if the specified file was found
if [ -z "$AnnoSINE_TE_File" ]; then
  echo "File *-matches.fa not found."
  exit 1
else
  # Extract the base name of the Annosine file without the path
  AnnoSINE_TE_File_Base=$(basename "$AnnoSINE_TE_File")

  # Add prefix to the sequences and store the result in a new file in the same directory
  Prefixed_AnnoSINE_TE_File="Prefixed_${AnnoSINE_TE_File_Base}"
  sed -E '/^>/ { s/^>/&ANNOSINE_/; s/ /_/g; }' "$AnnoSINE_TE_File" > "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_ANNOSINE_outputs/$Prefixed_AnnoSINE_TE_File"

  # Move the new file to the main directory
  mv "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_ANNOSINE_outputs/$Prefixed_AnnoSINE_TE_File" ./$final_outputs_folder

  # Notify that the file has been moved
  echo "File moved to $final_outputs_folder directory: $Prefixed_AnnoSINE_TE_File"
fi

end_time_annosine=$(date +%s)
elapsed_annosine=$((end_time_annosine - start_time_annosine))

echo ""
echo "--------------------FINISHED ANNOSINE | ELAPSED TIME: $((elapsed_annosine / 60)) min $((elapsed_annosine % 60)) sec--------------------"
echo ""


#HELIANO

start_time_heliano=$(date +%s)
echo ""
echo "--------------------STARTING HELIANO--------------------"
echo ""

#Make Heliano outputs folder inside of $TMPDIR
mkdir -p "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HELIANO_outputs"

apptainer run ./TE_pipeline_sif_files/heliano.sif heliano -g $genome -w 10000 -dm 2500 -pt 1 -is1 1 -is2 1 -sim_tir 100 -p 0.001 -s 32 --process $JOB_THREADS -o "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HELIANO_outputs"

# Find the specific file within the HELIANO output folder and store its path in a variable
HELIANO_TE_File=$(find "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HELIANO_outputs" -type f -name "RC.representative.fa")

# Simple check to see if the specified file was found
if [ -z "$HELIANO_TE_File" ]; then
  echo "File RC.representative.fa not found."
  exit 1
else
  # Extract the base name of the Heliano file without the path
  HELIANO_TE_File_Base=$(basename "$HELIANO_TE_File")

  # Add prefix to the sequences and store the result in a new file in the same directory
  Prefixed_HELIANO_TE_File="Prefixed_${HELIANO_TE_File_Base}"
  sed -E '/^>/ { s/^>/&HELIANO_/; s/ /_/g; }' "$HELIANO_TE_File" > "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HELIANO_outputs/$Prefixed_HELIANO_TE_File"

  # Move the new file to the main directory
  mv "$TMPDIR/TE_pipeline_intermediate_outputs/${base_name}_HELIANO_outputs/$Prefixed_HELIANO_TE_File" ./$final_outputs_folder

  # Notify that the file has been moved
  echo "File moved to $final_outputs_folder directory: $Prefixed_HELIANO_TE_File"
fi

end_time_heliano=$(date +%s)
elapsed_heliano=$((end_time_heliano - start_time_heliano))

echo ""
echo "--------------------FINISHED HELIANO | ELAPSED TIME: $((elapsed_heliano / 60)) min $((elapsed_heliano % 60)) sec--------------------"
echo ""


# MITEFINDER

start_time_mitefinder=$(date +%s)

echo ""
echo "--------------------STARTING MITEFINDER--------------------"
echo ""

# Make MITEFINDER outputs folder inside of $TMPDIR
mkdir -p "$TMPDIR/TE_pipeline_intermediate_outputs/mitefinder"

# Run MITEFINDER - output the ultimate file "mitefinder_file" in the folder $TMPDIR/mitefinder
~/miteFinder/bin/miteFinder -input $genome -output "$TMPDIR/TE_pipeline_intermediate_outputs/mitefinder/mitefinder_file" -pattern_scoring ~/miteFinder/profile/pattern_scoring.txt -threshold 0.5

# Define the expected file path
MITEFINDER_TE_File="$TMPDIR/TE_pipeline_intermediate_outputs/mitefinder/mitefinder_file"

# Check if the file exists
if [ ! -f "$MITEFINDER_TE_File" ]; then
    echo "File $MITEFINDER_TE_File not found."
    exit 1
else
    # Add prefix to the sequences and store the result in a new file in the same directory
    Prefixed_MITEFINDER_TE_File="prefixed_mitefinder_file"
    sed -E '/^>/ { s/^>/&MITEFINDER_/; s/ /_/g; }' "$MITEFINDER_TE_File" > "$TMPDIR/TE_pipeline_intermediate_outputs/mitefinder/$Prefixed_MITEFINDER_TE_File"

    # Move the prefixed file to the main directory
    mv "$TMPDIR/TE_pipeline_intermediate_outputs/mitefinder/$Prefixed_MITEFINDER_TE_File" ./$final_outputs_folder

    # Notify that the file has been moved
    echo "File moved to $final_outputs_folder directory: $Prefixed_MITEFINDER_TE_File"
fi

end_time_mitefinder=$(date +%s)
elapsed_mitefinder=$((end_time_mitefinder - start_time_mitefinder))

echo ""
echo "--------------------FINISHED MITEFINDER | ELAPSED TIME: $((elapsed_mitefinder / 60)) min $((elapsed_mitefinder % 60)) sec--------------------"
echo ""


# Combine all prefixed files into a single file
combined_file="COMBINED_TE_SEQUENCES_${base_name}.fa"
cat "./$final_outputs_folder/$Prefixed_EarlGrey_FamilyFile" "./$final_outputs_folder/$Prefixed_HiTE_TE_File" "./$final_outputs_folder/$Prefixed_AnnoSINE_TE_File" "./$final_outputs_folder/$Prefixed_HELIANO_TE_File" "./$final_outputs_folder/$Prefixed_MITEFINDER_TE_File" > "$combined_file"

# Check if the combined file was created - if not, print file not found message
if [ ! -f "$combined_file" ]; then
  echo "Combined file $combined_file not found."
  exit 1
fi

# Verify the content of the combined file - if no sequences are present in the file, print error message
if ! grep -q "^>" "$combined_file"; then
  echo "Combined file $combined_file contains no sequences."
  exit 1
fi



# CD-HIT ROUND @ 95%
# Load necessary modules for cd-hit
module purge
module load StdEnv/2020
module load gcc/13.3
module load cd-hit/4.8.1

# Run cd-hit-est - runs at 95% sequence coverage and 95% sequence identity threshold
cd-hit-est -i "$combined_file" -o "Clustered_COMBINED_TE_SEQUENCES_${base_name}" -d 0 -aS 0.95 -c 0.95 -G 0 -g 1 -b 500 -M $CDHIT_MEM_MB -T $JOB_THREADS

# Check if cd-hit-est ran successfully - print error message if not, confirmation message if yes
if [ $? -ne 0 ]; then
  echo "cd-hit-est encountered an error."
  exit 1
fi

echo "cd-hit-est ran successfully and output file is Clustered_COMBINED_TE_SEQUENCES_${base_name}"


# CD-HIT ROUND 2 @ 80%
# After the first round of cd-hit is finished and a FASTA of representative sequences is produced, pass that into the second round of cd-hit for clustering

# Run cd-hit-est - runs at 80% sequence coverage and 80% sequence identity threshold
cd-hit-est -i "Clustered_COMBINED_TE_SEQUENCES_${base_name}" -o "FINAL_cdhit_${base_name}" -d 0 -aS 0.80 -c 0.80 -G 0 -g 1 -b 500 -M $CDHIT_MEM_MB -T $JOB_THREADS

# Check if cd-hit-est ran successfully - print error message if not, confirmation message if yes
if [ $? -ne 0 ]; then
  echo "cd-hit-est encountered an error."
  exit 1
fi

echo "cd-hit-est ran successfully and output file is FINAL_cdhit_${base_name}"



# Virtual Environment Set-up

# Activate virtual environment with all the appropriate python libraries before calling format_data.py
module load python/3.11
echo "Python 3.11 loaded"

#Create a virtual environment if it doesn't already exist
if [ ! -d "PythonENV/PythonENV" ]; then
  virtualenv --no-download PythonENV/PythonENV
fi

#Activate the virtual environment
source PythonENV/PythonENV/bin/activate
echo "Virtual environment activated: $(which python)"
echo "pip version in virtual environment: $(pip --version)"

#upgrade pip
pip install --no-index --upgrade pip
echo "pip has been upgraded"

#Install necessary packages IF not already installed
declare -a packages=("pandas" "openpyxl" "biopython")

for package in "${packages[@]}"
do
  if ! python -c "import $package" &> /dev/null; then
    pip install $package --no-index
  else
    echo "$package is already installed."
  fi
done

#Activate R module
module load r/4.3.1
echo "r/4.3.1 loaded"


# Check if Python 3.11 and R 4.3.1 are loaded correctly - if not, print error message
if ! command -v python3 &> /dev/null; then
   echo "Failed to load Python 3.11"
   exit 1
fi

if ! command -v R &> /dev/null; then
   echo "Failed to load R 4.3.1"
   exit 1
fi

echo "environment set-up complete."



# format_data.py
# Calls the format_data.py script - ULTIMATELY OUTPUTS FINAL .csv FILE FOR USER
python ./Scripts/format_data.py "FINAL_cdhit_${base_name}.clstr"


# Add PFAM column to the main .CSV file

# This script will extract all the representative sequences from the main CSV file, that are still tagged with 'unknown', and check if there are any genes within any of these sequences.
python ./Scripts/extract_representative_sequences.py "COMPLETE_TE_RESULTS_${base_name}.csv" "FINAL_cdhit_${base_name}" "$base_name"

# SET UP PFAM SCAN DATABASE
# Directory where the PFAM database will be stored

# Set up variable names for different directory locations
PIPELINE_ROOT="$(pwd)" # This is just the location to the current working directory (This is the same as the variable working_directory)

REP_NUCLEOTIDE_FASTA="$PIPELINE_ROOT/Representative_Sequences_${base_name}.fasta" # This is a fasta containing all unkonwn consensus sequences from the main CSV file
REP_ORF_FASTA="$PIPELINE_ROOT/Representative_ORFs_${base_name}.faa" # This is a fasta containing those translated nucleotides to amino acids from the previous fasta

# Load EMBOSS (needs StdEnv/2020) and generate ORFs as proteins
module load StdEnv/2020
module load emboss/6.6.0

getorf \
  -sequence "$REP_NUCLEOTIDE_FASTA" -outseq "$REP_ORF_FASTA" -minsize 300

PFAM_DB_DIR="$PIPELINE_ROOT/Databases/pfamdb" # Directory where the PFAM database is stored
PFAM_SCAN_DIR="$PIPELINE_ROOT/Databases/pfam_scan" # Directory where the pfam_scan direcotory (which contains pfam_scan.py) is stored
MERGE_SCRIPT="$PIPELINE_ROOT/Scripts/merge.py" # Location of the merge.py script
OUTPUT_CSV="$PIPELINE_ROOT/pfam_output_${base_name}.csv" # Location of the pfam_output csv file

#Load HMMER Tool Suite, which includes hmmpress command
module load hmmer

# Check if Pfam library file (Pfam-A.hmm) already exists - if not, unzip the zipped file
if [ ! -f "$PFAM_DB_DIR/Pfam-A.hmm" ]; then
    # Unpack and prepare the database - currently, compressed files exist of the databse, therefore, unzip them
    gunzip -c $PFAM_DB_DIR/Pfam-A.hmm.dat.gz > $PFAM_DB_DIR/Pfam-A.hmm.dat
    gunzip -c $PFAM_DB_DIR/Pfam-A.hmm.gz > $PFAM_DB_DIR/Pfam-A.hmm
    rm $PFAM_DB_DIR/Pfam-A.hmm.gz $PFAM_DB_DIR/Pfam-A.hmm.dat.gz
else
    echo "Pfam database already set up."
fi

# Rename the Pfam-A.hmm file to make it specific to the genome running it. Also stores the copied HMM file in another directory.
mkdir -p "$PFAM_DB_DIR/pfamdb_${base_name}"
specified_HMM_File_name="Pfam-A_${base_name}.hmm"
cp "$PFAM_DB_DIR/Pfam-A.hmm" "$PFAM_DB_DIR/pfamdb_${base_name}/$specified_HMM_File_name"
cp "$PFAM_DB_DIR/Pfam-A.hmm.dat" "$PFAM_DB_DIR/pfamdb_${base_name}/${specified_HMM_File_name}.dat"

# prepares the Pfam-A HMM database file for use with HMMER
hmmpress "$PFAM_DB_DIR/pfamdb_${base_name}/$specified_HMM_File_name"

# Run pfam_scan.py to scan the FASTA file and get the output in CSV format
cd "$PFAM_SCAN_DIR"

# Debug paths
echo "Current directory: $(pwd)" # This will show you the current directory you are in - pfam_scan directory
echo "Contents of pfamdb_${base_name} directory:"
ls -lh "$PFAM_DB_DIR/pfamdb_${base_name}" # This will show you all the content in the Pfamdb directory which will be used in pfam_scan.py


PREPROCESSED_REP_ORF_FASTA="$PIPELINE_ROOT/Preprocessed_Representative_ORFs_${base_name}.faa" # Create a new variable to hold the preprocessed representative ORF fasta file path


# This renames the .faa headers to match those on the representative_sequence.fa file, so mapping can occur between the ORF file and the TE sequence headers present on the COMPLETE_CSV file
awk '
  /^>/ {
    split($0, a, " ");
    h = a[length(a)];          # last space-delimited token (no leading ">")
    sub(/^[^_]+_/, "", h);     # drop tool prefix + first underscore
    print ">" h;
    next
  }
  { print }
' "$REP_ORF_FASTA" > "$PREPROCESSED_REP_ORF_FASTA"


# Execute pfam_scan.py with corrected paths
./pfam_scan.py "$PREPROCESSED_REP_ORF_FASTA" "$PFAM_DB_DIR/pfamdb_${base_name}" -out "$OUTPUT_CSV" -outfmt csv

#rm compressed pfam files in pfamdb and the original ORF fasta file
rm -r "$PFAM_DB_DIR/pfamdb_${base_name}"
rm "$REP_ORF_FASTA"


# Notify user
echo "Pfam scan completed. Output saved to $OUTPUT_CSV"


#This final Python script will merge the pfam proteins into the main CSV
cd $PIPELINE_ROOT

python "$MERGE_SCRIPT" "COMPLETE_TE_RESULTS_${base_name}.csv" "$OUTPUT_CSV"



# ORGANIZING MAIN FOLDER
# Create necessary directories
mkdir -p $TMPDIR/earlgrey_genome_support_files
mkdir -p $TMPDIR/TE_fastas_from_TE_Pipelines
mkdir -p $TMPDIR/"cd-hit_round_1_outputs"
mkdir -p $TMPDIR/"cd-hit_round_2_outputs"
mkdir -p $TMPDIR/"pfam_intermediate_outputs"

# Define base names and patterns
Round1_cd_hit_prefix="Clustered_COMBINED_TE_SEQUENCES_${base_name}"
Round2_cd_hit_prefix="FINAL_cdhit_${base_name}"

# Loop through each file in the current directory
for file in *; do
   # Move intermediate EarlGrey files to earlgrey_genome_support_files
   if [[ "$file" == "${genome}.dict" ]] || [[ "$file" == "${genome}.bak.gz" ]] || [[ "$file" == "${genome}.prep" ]] || [[ "$file" == "${genome}.prep.bak" ]] || [[ "$file" == "${genome}.prep.fai" ]] || [[ "$file" == "${genome}.fai" ]]; then
      mv "$file" $TMPDIR/earlgrey_genome_support_files/

   # Move Round 1 cd-hit files to cd-hit_round_1_outputs
   elif [[ "$file" == ${Round1_cd_hit_prefix}* ]]; then
      mv "$file" $TMPDIR/"cd-hit_round_1_outputs/"

   # Move Round 2 cd-hit files to cd-hit_round_2_outputs - unless it is the final cd-hit FASTA sequence (so user can refer to it)
   elif [[ "$file" == ${Round2_cd_hit_prefix}?* ]]; then
      mv "$file" $TMPDIR/"cd-hit_round_2_outputs/"

   # Move Pfam outputs to pfam_intermediate_outputs
   elif [[ "$file" == "Representative_Sequences_${base_name}.fasta" ]] || [[ "$file" == "Preprocessed_Representative_ORFs_${base_name}.faa" ]] || [[ "$file" == "Representative_ORFs_${base_name}.faa" ]]; then
      mv "$file" $TMPDIR/"pfam_intermediate_outputs/"
   fi
done

# Loop through each file in the final_outputs_folder directory (as there are some there that need to be moved to $TMPDIR)
for file in ./$final_outputs_folder/*; do
   # Move TE fasta files to TE_fastas_from_TE_Pipelines - NOTE: the 'basename' command is essential here before "$file" for this loop to work properly
   if [[ "$(basename "$file")" == "$Prefixed_EarlGrey_FamilyFile" ]] || [[ "$(basename "$file")" == "$Prefixed_HiTE_TE_File" ]] || [[ "$(basename "$file")" == "$Prefixed_AnnoSINE_TE_File" ]] || [[ "$(basename "$file")" == "$Prefixed_HELIANO_TE_File" ]] || [[ "$(basename "$file")" == "$Prefixed_MITEFINDER_TE_File" ]]; then
      mv "$file" $TMPDIR/TE_fastas_from_TE_Pipelines/
   fi
done

# Finally, move the final output files to the 'final_outputs_folder' directory so that all of the associated files are in one place
mv "COMPLETE_TE_RESULTS_${base_name}.csv" $final_outputs_folder
mv "FINAL_cdhit_${base_name}" $final_outputs_folder
mv "$combined_file" $final_outputs_folder
mv "$OUTPUT_CSV" $final_outputs_folder


# Depending on what the user specifies in flags, according outputs directories/files to the main directory from $TMPDIR

echo ""
if [[ $tool_outputs == true ]]; then
   mv "$TMPDIR/TE_pipeline_intermediate_outputs/" ./$final_outputs_folder
   echo "TE_pipeline_intermediate_outputs moved to the $final_outputs_folder directory"
fi

if [[ $earlgrey_outputs == true ]]; then
   mv "$TMPDIR/earlgrey_genome_support_files/" ./$final_outputs_folder
   echo "earlgrey_genome_support_files moved to the $final_outputs_folder directory"
fi

if [[ $prefixed_file_outputs == true ]]; then
   mv "$TMPDIR/TE_fastas_from_TE_Pipelines/" ./$final_outputs_folder
   echo "TE_fastas_from_TE_Pipelines moved to the $final_outputs_folder directory"
fi

if [[ $cd_hit_outputs == true ]]; then
   mv "$TMPDIR/cd-hit_round_1_outputs/" ./$final_outputs_folder
   mv "$TMPDIR/cd-hit_round_2_outputs/" ./$final_outputs_folder
   echo "cd-hit_round_1_outputs and cd-hit_round_2_outputs moved to the $final_outputs_folder directory"
fi

if [[ $pfam_outputs == true ]]; then
   mv "$TMPDIR/pfam_intermediate_outputs/" ./$final_outputs_folder
   echo "pfam_intermediate_outputs  moved to the $final_outputs_folder directory"
fi

