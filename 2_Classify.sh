#!/bin/bash
#SBATCH --time=0-02:00:00
#SBATCH --account=def-skremer
#SBATCH --cpus-per-task=12
#SBATCH --mem=26G
#SBATCH --mail-user=mahmad15@uoguelph.ca
#SBATCH --mail-type=BEGIN,END,FAIL

# NOTE: Classify unknown sequences using a trained model.
# Required positional args (6):
#   1) COMPLETE_TE_RESULTS_*.csv
#   2) CD-HIT output (from first half of the pipeline)
#   3) trained model .pkl
#   4) scaler .pkl
#   5) label encoder .pkl
#   6) feature selector .pkl
#
# Optional flag:
#   --classifier-threshold <float>
#
# Outputs:
#   Python creates AI_Classification_Results/ and Intermediate_dataset_files/
#   These are copied to Classification_Results/, then both
#   Classification_Results/ and Intermediate_dataset_files/ are moved into
#   Classification_Outputs/.

set -euo pipefail

usage() {
  echo "Usage:"
  echo "  sbatch 2_Classify.sh <complete_csv> <cdhit_output> <model_pkl> <scaler_pkl> <label_encoder_pkl> <selector_pkl> [--classifier-threshold <float>]"
  echo
  echo "Example:"
  echo "  sbatch 2_Classify.sh COMPLETE_TE_RESULTS_run.csv FINAL_CD_HIT_run.fasta model.pkl scaler.pkl label_encoder.pkl selector.pkl --classifier-threshold 0.70"
}

# Need at least 6 args (the 6 required), allow optional 8 with the threshold flag
if [[ $# -lt 6 ]]; then
  echo "Error: 6 required arguments missing."
  usage
  exit 1
fi

# Pull the 6 required positional args, then shift them off
COMPLETE_CSV="$1"
CDHIT_OUT="$2"
MODEL_PKL="$3"
SCALER_PKL="$4"
LABEL_PKL="$5"
SELECTOR_PKL="$6"
shift 6

# Anything left is optional flags; we only accept --classifier-threshold <float>
if [[ $# -gt 0 ]]; then
  if [[ $# -ne 2 || "$1" != "--classifier-threshold" ]]; then
    echo "Error: Unrecognized optional arguments."
    usage
    exit 1
  fi
fi

# Sanity checks on required files
for f in "$COMPLETE_CSV" "$CDHIT_OUT" "$MODEL_PKL" "$SCALER_PKL" "$LABEL_PKL" "$SELECTOR_PKL"; do
  [[ -f "$f" ]] || { echo "Error: file not found: $f"; exit 1; }
done

module purge
module load python/3.11
module load r/4.3.1

cd "$SLURM_SUBMIT_DIR"
export PYTHONUNBUFFERED=1

# Run classifier (Python creates AI_Classification_Results/ and Intermediate_dataset_files/)
python -u Classify/_START_CLASSIFYING.py \
  "$COMPLETE_CSV" \
  "$CDHIT_OUT" \
  "$MODEL_PKL" \
  "$SCALER_PKL" \
  "$LABEL_PKL" \
  "$SELECTOR_PKL" \
  "$@"

# -----------------------------
# Collect final outputs
# -----------------------------
SRC_DIR="AI_Classification_Results"
DEST_DIR="Classification_Results"
mkdir -p "$DEST_DIR"

if [[ -d "$SRC_DIR" ]]; then
  cp -r "$SRC_DIR"/. "$DEST_DIR"/
  rm -rf "$SRC_DIR"
fi

# -----------------------------
# Consolidate everything
# -----------------------------
FINAL_OUT="Classification_Outputs"
mkdir -p "$FINAL_OUT"

for d in "$DEST_DIR" "Intermediate_dataset_files"; do
  if [[ -d "$d" ]]; then
    mv "$d" "$FINAL_OUT"/
  fi
done

# -----------------------------
# Keep the ORIGINAL training dataset CSV in place
# Derive its base name from the scaler file: SCALER_<name>.pkl -> <name>
# If <name>.csv or <name>.CSV got moved inside Intermediate_dataset_files,
# move it back to the project root.
# -----------------------------
scaler_base="$(basename "$SCALER_PKL")"
orig_base="${scaler_base#SCALER_}"
orig_base="${orig_base%.pkl}"

for ext in csv CSV; do
  src_path="${FINAL_OUT}/Intermediate_dataset_files/${orig_base}.${ext}"
  if [[ -f "$src_path" ]]; then
    mv "$src_path" .
  fi
done









