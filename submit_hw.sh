#!/usr/bin/env bash
set -euo pipefail

# Unified homework submission helper.
# Usage: ./submit_hw.sh <hw_directory> <LASTNAME> <FIRSTNAME> <STUDENTID> [--notest]

usage() {
  echo "Usage: $0 <hw_directory> <LASTNAME> <FIRSTNAME> <STUDENTID> [--notest]"
  echo "Example: $0 hw0_hello_world SMITH JOHN 11223344"
}

if [ "$#" -ne 4 ] && { [ "$#" -ne 5 ] || [ "${5:-}" != "--notest" ]; }; then
  usage
  exit 1
fi

HW_INPUT=$1
LASTNAME=$2
FIRSTNAME=$3
STUDENTID=$4
SKIP_TESTS=false
if [ "${5:-}" = "--notest" ]; then
  SKIP_TESTS=true
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

case "$HW_INPUT" in
  /*) HW_CANDIDATE=$HW_INPUT ;;
  *)  HW_CANDIDATE="$SCRIPT_DIR/$HW_INPUT" ;;
esac

if [ ! -d "$HW_CANDIDATE" ]; then
  echo "Error: homework directory '$HW_INPUT' was not found."
  exit 1
fi

HW_DIR="$(cd -- "$HW_CANDIDATE" && pwd -P)"
ASSIGN_NAME="$(basename -- "$HW_DIR")"

# Only package a direct child of this repository. This prevents an accidental
# absolute path or '..' argument from archiving unrelated files.
if [ "$(dirname -- "$HW_DIR")" != "$SCRIPT_DIR" ]; then
  echo "Error: '$HW_INPUT' must be a homework directory directly under $SCRIPT_DIR."
  exit 1
fi

if [[ ! "$ASSIGN_NAME" =~ ^hw([0-9]+)(_.+)?$ ]]; then
  echo "Error: '$ASSIGN_NAME' must be named like hw0_hello_world or hw1_bpe_and_lm."
  exit 1
fi
HW_NUM=${BASH_REMATCH[1]}

for value in "$LASTNAME" "$FIRSTNAME" "$STUDENTID"; do
  if [[ ! "$value" =~ ^[[:alnum:].-]+$ ]]; then
    echo "Error: name and student ID fields may contain only letters, numbers, dots, and hyphens."
    exit 1
  fi
done

for command_name in zip unzip; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Error: '$command_name' is required but was not found on PATH."
    exit 1
  fi
done
if [ "$SKIP_TESTS" = false ] && ! command -v uv >/dev/null 2>&1; then
  echo "Error: 'uv' is required to run the assignment tests but was not found on PATH."
  exit 1
fi

IGNORE_FILE="$HW_DIR/.submission_ignore"
IGNORE_PATTERNS=()
if [ -f "$IGNORE_FILE" ]; then
  echo "Using exclusions from $IGNORE_FILE"
  while IFS= read -r raw_pattern || [ -n "$raw_pattern" ]; do
    pattern=${raw_pattern%$'\r'}
    pattern="${pattern#"${pattern%%[![:space:]]*}"}"
    pattern="${pattern%"${pattern##*[![:space:]]}"}"
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    pattern=${pattern#./}
    if [[ "$pattern" = /* || "$pattern" = ".." || "$pattern" = ../* || "$pattern" = */../* || "$pattern" = */.. ]]; then
      echo "Error: unsafe pattern '$pattern' in $IGNORE_FILE."
      exit 1
    fi
    IGNORE_PATTERNS+=("$pattern")
  done < "$IGNORE_FILE"
fi

if [ "$SKIP_TESTS" = false ]; then
  echo "Running tests for $ASSIGN_NAME..."
  PYTEST_ARGS=(-q)
  for pattern in "${IGNORE_PATTERNS[@]}"; do
    PYTEST_ARGS+=("--ignore-glob=$pattern")
  done
  if ! uv run --directory "$HW_DIR" pytest "${PYTEST_ARGS[@]}"; then
    echo "Tests failed. Fix failures before submitting."
    exit 1
  fi
  echo "Tests passed. Creating submission..."
else
  echo "Warning: skipping tests as requested. Creating submission..."
fi

SUBMISSION_ZIP="hw${HW_NUM}_submission_${LASTNAME}_${FIRSTNAME}_${STUDENTID}.zip"
OUTPUT_DIR="$(pwd -P)"
OUTPUT_PATH="$OUTPUT_DIR/$SUBMISSION_ZIP"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nlpdl-submission.XXXXXX")"
TEMP_ZIP="$TEMP_DIR/$SUBMISSION_ZIP"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# Info-ZIP matches these patterns against complete archive paths. Both the
# directory entry and its descendants are excluded so no empty cache folders
# remain in the result.
ZIP_EXCLUDES=(
  "$ASSIGN_NAME/.git" "$ASSIGN_NAME/.git/*" "*/.git" "*/.git/*"
  "$ASSIGN_NAME/.venv" "$ASSIGN_NAME/.venv/*" "*/.venv" "*/.venv/*"
  "$ASSIGN_NAME/.pytest_cache" "$ASSIGN_NAME/.pytest_cache/*" "*/.pytest_cache" "*/.pytest_cache/*"
  "$ASSIGN_NAME/__pycache__" "$ASSIGN_NAME/__pycache__/*" "*/__pycache__" "*/__pycache__/*"
  "$ASSIGN_NAME/uv.lock" "*/uv.lock"
  "*.pyc" "*.pyo"
  "$ASSIGN_NAME/hw${HW_NUM}_submission_*.zip"
  "$ASSIGN_NAME/${ASSIGN_NAME}_submission" "$ASSIGN_NAME/${ASSIGN_NAME}_submission/*"
)

for pattern in "${IGNORE_PATTERNS[@]}"; do
  pattern=${pattern%/}
  ZIP_EXCLUDES+=("$ASSIGN_NAME/$pattern" "$ASSIGN_NAME/$pattern/*")
done

(
  cd -- "$SCRIPT_DIR"
  zip -q -r "$TEMP_ZIP" "$ASSIGN_NAME/" -x "${ZIP_EXCLUDES[@]}"
)

if ! unzip -tqq "$TEMP_ZIP"; then
  echo "Error: ZIP integrity check failed."
  exit 1
fi

BAD_ROOT="$(unzip -Z1 "$TEMP_ZIP" | awk -v root="$ASSIGN_NAME/" 'index($0, root) != 1 && !found { print; found = 1 }')"
if [ -n "$BAD_ROOT" ]; then
  echo "Error: archive entry '$BAD_ROOT' is outside the required $ASSIGN_NAME/ directory."
  exit 1
fi

BAD_GENERATED="$(unzip -Z1 "$TEMP_ZIP" | awk '/(^|\/)(\.git|\.venv|\.pytest_cache|__pycache__|uv\.lock)(\/|$)|\.py[co]$/ && !found { print; found = 1 }')"
if [ -n "$BAD_GENERATED" ]; then
  echo "Error: generated/cache entry '$BAD_GENERATED' unexpectedly remained in the archive."
  exit 1
fi

mv -f -- "$TEMP_ZIP" "$OUTPUT_PATH"

echo "Submission created: $OUTPUT_PATH"
echo "Contents:"
unzip -l "$OUTPUT_PATH"
