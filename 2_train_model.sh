#!/bin/bash
#SBATCH -t 0-01:00:00
#SBATCH --mem=10G
#SBATCH -c 6
#SBATCH --mail-user=your@email.com
#SBATCH --mail-type=BEGIN,FAIL,END
#SBATCH --account=INPUT_ACCOUNT

# NOTE: This script will train a model on a new dataset. The corresponding outputs
# (training metrics, pickle artifacts, visualizations, and intermediate CSVs)
# will be gathered into a directory named:
#   Training_Outputs-<dataset_name_without_extension>

set -euo pipefail

usage() {
  echo "Usage:"
  echo "  sbatch 3_Train_Model.sh <dataset.csv> [--kbest <int>] [--n-estimators <int>]"
  echo
  echo "Examples:"
  echo "  sbatch 3_Train_Model.sh training_dataset.csv"
  echo "  sbatch 3_Train_Model.sh training_dataset.csv --kbest 50 --n-estimators 300"
}

# --- Parse args: dataset (required), --kbest (optional), --n-estimators (optional) ---
DATASET=""
KBEST=""
NESTIM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --kbest)
      [[ $# -ge 2 ]] || { echo "Error: --kbest needs a value."; usage; exit 1; }
      KBEST="$2"; shift 2
      ;;
    --n-estimators|--n-est)
      [[ $# -ge 2 ]] || { echo "Error: --n-estimators needs a value."; usage; exit 1; }
      NESTIM="$2"; shift 2
      ;;
    -*)
      echo "Error: Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [[ -z "$DATASET" ]]; then
        DATASET="$1"; shift
      else
        echo "Error: Unexpected extra argument: $1"
        usage
        exit 1
      fi
      ;;
  esac
done

# Require dataset
if [[ -z "$DATASET" ]]; then
  echo "Error: <dataset.csv> is required."
  usage
  exit 1
fi

# Check dataset path exists (relative to submit dir)
if [[ ! -f "$DATASET" ]]; then
  echo "Error: dataset not found: $DATASET"
  exit 1
fi

module purge
module load python/3.11
module load r/4.3.1

cd "$SLURM_SUBMIT_DIR"
export PYTHONUNBUFFERED=1

# ---- Use path relative to the submit directory (your current project dir) ----
PY_SCRIPT="Train/_START_TRAINING.py"
if [[ ! -f "$PY_SCRIPT" ]]; then
  echo "Error: _START_TRAINING.py not found at $(pwd)/$PY_SCRIPT"
  exit 1
fi
# ------------------------------------------------------------------------------

# Build Python args
PY_ARGS=( "$PY_SCRIPT" "$DATASET" )
[[ -n "$KBEST" ]]  && PY_ARGS+=( --kbest "$KBEST" )
[[ -n "$NESTIM" ]] && PY_ARGS+=( --n-estimators "$NESTIM" )

python -u "${PY_ARGS[@]}"

# -----------------------------
# Move final outputs to folder
# -----------------------------

# Derive dataset base name (strip path & final extension, case-agnostic)
DATASET_NAME="$(basename "$DATASET")"
DATASET_BASE="${DATASET_NAME%.*}"

# Personalized output folder at project root
INT_DIR="Training_Outputs-${DATASET_BASE}"
mkdir -p "$INT_DIR"

# Helper to move a dir if it exists
move_if_exists () {
  local src="$1"
  if [[ -d "$src" ]]; then
    mv "$src" "$INT_DIR"/
  fi
}

# Your Python currently writes these at the project root. If that ever changes to Train/,
# the following lines handle both locations without errors or warnings.
move_if_exists "Model_Artifacts"
move_if_exists "Visualizations"
move_if_exists "Intermediate_dataset_files"

move_if_exists "Train/Model_Artifacts"
move_if_exists "Train/Visualizations"
move_if_exists "Train/Intermediate_dataset_files"

echo "Gathered training outputs in: $INT_DIR"
