#!/usr/bin/env bash
set -euo pipefail

echo "Running terraform test...🧨"

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform is not installed or not in PATH.💥"
  echo "Install it on macOS with:"
  echo "  brew install terraform"
  echo ""
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TF_ROOT="terraform"

# Same push-scope logic as terraform-validate.sh, measured against origin/main
# rather than the branch's own upstream. Comparing against @{u} made both hooks
# skip on `git push origin HEAD:main`, which is this repository's merge
# workflow — see the longer note in terraform-validate.sh.
get_changed_files() {
  local base
  if base="$(git merge-base HEAD origin/main 2>/dev/null)"; then
    git diff --name-only "${base}..HEAD" 2>/dev/null || true
  fi
}

scope_unknown=false
if ! git merge-base HEAD origin/main >/dev/null 2>&1; then
  scope_unknown=true
fi

has_tf_changes=false
while IFS= read -r line; do
  [ -z "$line" ] && continue
  [[ "$line" == *.tf || "$line" == *.tftest.hcl ]] || continue
  [[ "$line" == "$TF_ROOT"/* ]] || continue
  has_tf_changes=true
  break
done < <(get_changed_files)

if [ "$scope_unknown" = true ]; then
  echo "Could not determine push scope (no upstream and no origin/main); running every suite."
elif [ "$has_tf_changes" = false ]; then
  echo "No Terraform changes under ${TF_ROOT}/. Skipping terraform test.✅"
  exit 0
fi

# A directory is testable if it holds .tftest.hcl files, whether those sit in
# tests/ or beside the configuration.
test_dirs=()
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  test_dirs+=("${dir#"${REPO_ROOT}"/}")
done < <(
  find "${REPO_ROOT}/${TF_ROOT}" -type f -name '*.tftest.hcl' -not -path '*/.terraform/*' 2>/dev/null \
    | while IFS= read -r f; do dirname "$f" | sed 's#/tests$##'; done \
    | sort -u
)

if [ "${#test_dirs[@]}" -eq 0 ]; then
  echo "No Terraform test suites found under ${TF_ROOT}/. Skipping terraform test.✅"
  exit 0
fi

# Isolated TF_DATA_DIR per suite, so this never re-initialises a developer's
# real .terraform/ and detaches it from remote state.
SCRATCH_ROOT="$(mktemp -d -t lizard-tftest.XXXXXX)"
cleanup() {
  rm -rf "$SCRATCH_ROOT"
}
trap cleanup EXIT INT TERM HUP

failed_dirs=()

for dir in "${test_dirs[@]}"; do
  abs_dir="${REPO_ROOT}/${dir}"

  echo ""
  echo "Testing ${dir}..."

  scratch_data_dir="${SCRATCH_ROOT}/$(echo "$dir" | tr '/' '_')"
  mkdir -p "$scratch_data_dir"

  if ! (
    cd "$abs_dir" \
      && TF_DATA_DIR="$scratch_data_dir" terraform init \
        -backend=false \
        -input=false \
        -no-color >/dev/null \
      && TF_DATA_DIR="$scratch_data_dir" terraform test -no-color
  ); then
    echo "terraform test failed in ${dir} ❌"
    failed_dirs+=("$dir")
  else
    echo "${dir} tested ✅"
  fi
done

if [ "${#failed_dirs[@]}" -ne 0 ]; then
  echo ""
  echo "Error: terraform test failed in the following directories:💥"
  for d in "${failed_dirs[@]}"; do
    echo "  - $d"
  done
  exit 1
fi

echo ""
echo "terraform test passed ✅"
