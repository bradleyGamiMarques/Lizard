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

# Which files this push would land, measured against origin/main.
#
# An earlier version compared against the branch's own upstream (@{u}). That is
# wrong for this repository's merge workflow: `git push origin HEAD:main` pushes
# to a ref that is not the branch's upstream, so once the branch had been pushed
# @{u}..HEAD was empty and both pre-push hooks skipped — on the one push that
# actually lands code on main. Commit locally, skip pushing the branch, FF-push
# to main, and nothing was checked at all. CI does not cover it either; the
# Terraform workflow only runs on pull_request.
#
# origin/main is the right baseline for both cases. On a feature branch it is
# the branch's own commits; on an FF-push to main it is exactly what is landing.
# It re-checks earlier commits on later pushes to a long branch, which is a
# cheap price for a guard that no longer skips when it matters.
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

# Any directory under terraform/ holding .tf files is a stack, at any depth.
#
# This deliberately does not stop at the first level: modules live in
# terraform/modules/<name>/ and examples in terraform/examples/<name>/, and an
# earlier version of this script only looked one level down, so both were
# skipped entirely and shipped unvalidated.
#
# .terraform/ is excluded because provider caches contain vendored .tf files
# that are not ours to validate.
stacks=()
while IFS= read -r dir; do
  [ -z "$dir" ] && continue
  stacks+=("${dir#"${REPO_ROOT}"/}")
done < <(
  find "${REPO_ROOT}/${TF_ROOT}" -type f -name '*.tf' -not -path '*/.terraform/*' 2>/dev/null \
    | while IFS= read -r f; do dirname "$f"; done \
    | sort -u
)

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
