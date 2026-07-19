#!/usr/bin/env bash
set -euo pipefail

echo "Running tflint...🧨"

if ! command -v tflint >/dev/null 2>&1; then
  echo "Error: tflint is not installed or not in PATH.💥"
  echo "Install it on macOS with:"
  echo "  brew install tflint"
  echo ""
  echo "tflint is required for Terraform linting in pre-commit."
  exit 1
fi

TF_ROOT="terraform"

has_staged_tf_files=false

while IFS= read -r path; do
  [[ "$path" == *.tf ]] || continue
  [[ "$path" == "$TF_ROOT"/* ]] || continue
  has_staged_tf_files=true
  break
done < <(git diff --cached --name-only --diff-filter=ACM || true)

if [ "$has_staged_tf_files" = false ]; then
  echo "No staged Terraform files under ${TF_ROOT}/. Skipping tflint.✅"
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "Running tflint --recursive from repo root: ${REPO_ROOT}"

if ! (cd "$REPO_ROOT" && tflint --recursive --chdir="$TF_ROOT"); then
  echo ""
  echo "Warning: tflint found issues. Please fix them before committing.⚠️"
  exit 1
fi

echo "tflint passed ✅"
