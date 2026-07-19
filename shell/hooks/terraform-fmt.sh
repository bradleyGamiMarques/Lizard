#!/usr/bin/env bash
set -euo pipefail

echo "Running terraform fmt...🧨"

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform is not installed or not in PATH.💥"
  echo "Install it on macOS with:"
  echo "  brew install terraform"
  echo ""
  exit 1
fi

TF_ROOT="terraform"

staged_tf_files=""

while IFS= read -r path; do
  [[ "$path" == *.tf ]] || continue
  [[ "$path" == "$TF_ROOT"/* ]] || continue

  if [ -z "$staged_tf_files" ]; then
    staged_tf_files="$path"
  else
    staged_tf_files="${staged_tf_files}"$'\n'"$path"
  fi
done < <(git diff --cached --name-only --diff-filter=ACM || true)

if [ -z "$staged_tf_files" ]; then
  echo "No staged Terraform files under ${TF_ROOT}/. Skipping terraform fmt.✅"
  exit 0
fi

echo "Staged Terraform files:"

for f in $staged_tf_files; do
  echo "  - $f"
done

echo ""

failed=0

for f in $staged_tf_files; do
  if [ -f "$f" ]; then
    echo "  terraform fmt $f"

    if ! terraform fmt "$f"; then
      failed=1
    fi
  fi
done

if [ "$failed" -ne 0 ]; then
  echo ""
  echo "Error: terraform fmt failed.💥"
  exit 1
fi

changed_after_fmt="$(git diff --name-only -- $staged_tf_files || true)"

if [ -n "$changed_after_fmt" ]; then
  echo ""
  echo "Warning: terraform fmt made changes to your staged Terraform files.⚠️"
  echo "Please review and stage the updated files:"
  echo "  git add $changed_after_fmt"
  echo ""
  exit 1
fi

echo "terraform fmt passed ✅"
