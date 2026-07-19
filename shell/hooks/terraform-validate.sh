#!/usr/bin/env bash
set -euo pipefail

echo "Running terraform validate...🧨"

if ! command -v terraform >/dev/null 2>&1; then
  echo "Error: terraform is not installed or not in PATH.💥"
  echo "Install it on macOS with:"
  echo "  brew install terraform"
  echo ""
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TF_ROOT="terraform"

# Determine which .tf files are changing in this push. For a pre-push hook the
# relevant set is "commits on HEAD that aren't yet upstream" — git diff
# @{u}..HEAD. A brand-new branch has no upstream on its first push, so fall
# back to comparing against origin/main.
get_changed_files() {
  local upstream
  if upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
    git diff --name-only "${upstream}..HEAD" 2>/dev/null || true
    return
  fi

  local base
  if base="$(git merge-base HEAD origin/main 2>/dev/null)"; then
    git diff --name-only "${base}..HEAD" 2>/dev/null || true
    return
  fi
}

scope_unknown=false
if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 \
  && ! git merge-base HEAD origin/main >/dev/null 2>&1; then
  scope_unknown=true
fi

has_tf_changes=false
while IFS= read -r line; do
  [ -z "$line" ] && continue
  [[ "$line" == *.tf ]] || continue
  [[ "$line" == "$TF_ROOT"/* ]] || continue
  has_tf_changes=true
  break
done < <(get_changed_files)

if [ "$scope_unknown" = true ]; then
  echo "Could not determine push scope (no upstream and no origin/main); validating every stack."
elif [ "$has_tf_changes" = false ]; then
  echo "No Terraform changes under ${TF_ROOT}/. Skipping terraform validate.✅"
  exit 0
fi

# Every immediate subdirectory of terraform/ holding .tf files is a stack.
# Discovering them beats a hardcoded list, which silently goes stale the first
# time someone adds a stack and forgets to update this script.
stacks=()
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  compgen -G "${dir}/*.tf" >/dev/null || continue
  stacks+=("${dir#"${REPO_ROOT}"/}")
done < <(find "${REPO_ROOT}/${TF_ROOT}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

if [ "${#stacks[@]}" -eq 0 ]; then
  echo "No Terraform stacks found under ${TF_ROOT}/. Skipping terraform validate.✅"
  exit 0
fi

# Use an isolated TF_DATA_DIR per stack so this hook never touches a developer's
# existing .terraform/ directory, which is likely already initialised against the
# real S3 backend. Re-initialising it here with -backend=false would quietly
# detach their working copy from remote state. The trap removes the scratch dir
# on every exit path: success, set -e failure, or signal.
SCRATCH_ROOT="$(mktemp -d -t lizard-tfvalidate.XXXXXX)"
cleanup() {
  rm -rf "$SCRATCH_ROOT"
}
trap cleanup EXIT INT TERM HUP

failed_stacks=()

for stack in "${stacks[@]}"; do
  abs_dir="${REPO_ROOT}/${stack}"

  echo ""
  echo "Validating ${stack}..."

  scratch_data_dir="${SCRATCH_ROOT}/$(echo "$stack" | tr '/' '_')"
  mkdir -p "$scratch_data_dir"

  if ! (
    cd "$abs_dir" \
      && TF_DATA_DIR="$scratch_data_dir" terraform init \
        -backend=false \
        -input=false \
        -no-color >/dev/null \
      && TF_DATA_DIR="$scratch_data_dir" terraform validate -no-color
  ); then
    echo "terraform validate failed in ${stack} ❌"
    failed_stacks+=("$stack")
  else
    echo "${stack} validated ✅"
  fi
done

if [ "${#failed_stacks[@]}" -ne 0 ]; then
  echo ""
  echo "Error: terraform validate failed in the following stacks:💥"
  for s in "${failed_stacks[@]}"; do
    echo "  - $s"
  done
  exit 1
fi

echo ""
echo "terraform validate passed ✅"
