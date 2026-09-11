#!/usr/bin/env bash
set -euo pipefail

# Usage: ./make_submission.sh <LASTNAME> <FIRSTNAME> <STUDENTID> [--notest]

ASSIGN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$ASSIGN_DIR/.." && pwd -P)"

cd -- "$ASSIGN_DIR"
exec "$REPO_ROOT/submit_hw.sh" "$ASSIGN_DIR" "$@"
