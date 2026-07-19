# Lizard

IaC that stops or terminates AWS resources when a CloudWatch billing
alarm enters the ALARM state. The repository is **tooling-only so far** — there
are no `.tf` files yet.

## Merging PRs — never use the "Rebase and merge" button

Commits on `main` must be signed and show GitHub **Verified**. The "Rebase and
merge" button replays commits as new SHAs with a rewritten committer, which
invalidates the signature — GitHub drops it and does not re-sign, so the result
lands on `main` as Unverified. Recovering from that means rewriting history,
which the rulesets below make impossible on `main`. Do not press the button.

Merge by fast-forwarding `main` instead. Everything below follows from one rule:

> **`main` only ever moves forward, and the commit that becomes its tip must be
> the exact object the PR points at.** GitHub marks a PR merged when *its head
> SHA* becomes reachable from `main` — it matches on that SHA, never on content.

### 1. Branch from a fresh `main`

```bash
git switch main && git pull
git switch -c dev/bradleyGamiMarques/<type>/<summary>
```

### 2. Commit, push, open the PR

The `commit-msg` hook lints each message as you go.

```bash
git push
gh pr create --base main
```

### 3. Wait for CI to pass

### 4. Preflight — this decides which merge path you are on

```bash
git switch <branch>
git pull --ff-only          # pulls any commits made in the GitHub web UI
git fetch origin main
git merge-base --is-ancestor origin/main HEAD && echo "FF OK" || echo "REBASE NEEDED"
```

**The pull is not optional.** Any commit made through the web UI — a README
tweak, an accepted review suggestion — lands on the PR branch but not in your
local checkout. Push without pulling and the changes reach `main` while the PR
stays **open**, because its head is a commit you never pushed. This happened on
PR #2: three of four commits landed, and it only went purple once the fourth
did.

### 5a. `FF OK` — `main` has not moved

```bash
git push origin HEAD:main
```

### 5b. `REBASE NEEDED` — something landed on `main` first

```bash
git rebase origin/main       # commit.gpgsign=true re-signs each commit as yours
git push --force-with-lease  # update the PR branch FIRST
git push origin HEAD:main
```

**This order is not optional either.** Rebasing gives every commit a new SHA.
Push those to `main` before updating the PR branch and the PR's head points at
abandoned commits, so it never goes purple — the same failure as PR #2, reached
a different way.

### 6. Verify, then clean up

The repository has `delete_branch_on_merge` enabled, and it **does** fire for
merges GitHub detects from an FF push, not only for ones performed by the merge
button — confirmed on PR #3. The remote branch is removed for you, so only the
local side needs cleaning up.

```bash
gh pr view <n> --json state --jq .state     # want MERGED
git switch main && git pull
git branch -d <branch>                      # -d, not -D: refuses if not merged
git fetch --prune                           # drop the stale remote-tracking ref
```

### Recommended local config

These are per-clone and do **not** travel with the repository, so each
contributor sets them individually:

```bash
git config pull.ff only               # plain `git pull` can only fast-forward
git config commit.gpgsign true        # rebase re-signs each commit with your key
git config gpg.format ssh
git config user.signingkey ~/.ssh/<your-key>
git config push.autoSetupRemote true  # `git push` works on a fresh branch
```

`commit.gpgsign=true` is what makes step 5b safe: without it a rebase produces
unsigned commits, and `required_signatures` should reject the push outright.

Two aliases worth having — `slog` to read signature status at a glance, and
`ffcheck` to run the step 4 preflight and print the command it implies:

```bash
git config --global alias.slog "log --pretty='%h %G? %GS  %s'"

git config --global alias.ffcheck '!f() { b="${1:-main}"; git fetch -q origin "$b" || { echo "fetch failed"; return 1; }; if git merge-base --is-ancestor "origin/$b" HEAD; then echo "FF OK        -> git push origin HEAD:$b"; else echo "REBASE NEEDED -> git rebase origin/$b && git push --force-with-lease"; fi; }; f'
```

```console
$ git ffcheck
FF OK        -> git push origin HEAD:main
```

| Method | Linear | Keeps commits | Verified |
| --- | --- | --- | --- |
| Rebase and merge (button) | yes | yes | **NO** |
| Squash and merge | yes | **no** | yes (GitHub's key) |
| Create a merge commit | **no** | yes | yes (your key) |
| **Local FF push** | yes | yes | yes (your key) |

The `required_signatures` rule below should cause the rebase button's unsigned
output to be rejected rather than silently landing — but do not lean on that,
just don't press it.

## Reading signature status

```bash
git log --format='%h %G? %s'
```

- `G` — good signature, signed with your key.
- `E` — **cannot check**, which is not the same as unsigned. Commits authored in
  the GitHub web UI are signed with GitHub's `web-flow` key, which is not in
  your local keyring. They are Verified on GitHub. **Leave them alone** — they
  do not need a re-signing rebase.
- `N` — genuinely unsigned. This is the only one worth fixing.

`e89a910`, `db861ce`, and `119d9df` are all `E` and all Verified on GitHub.
Confirm rather than guess:

```bash
gh api repos/bradleyGamiMarques/Lizard/commits/<sha> \
  --jq '.commit.verification | {verified, reason}'
```

## `main` is protected by rulesets, not classic branch protection

`gh api repos/.../branches/main/protection` returns **404** here. That does not
mean `main` is unprotected — protection lives in rulesets, which are a separate
API:

```bash
gh api repos/bradleyGamiMarques/Lizard/rulesets
```

| Ruleset | Rules | Bypass |
| --- | --- | --- |
| `main integrity` | deletion, non_fast_forward, required_linear_history, required_signatures | **none — applies to the owner too** |
| `main requires PR` | pull_request | RepositoryRole, always |

Two consequences:

- **History on `main` cannot be rewritten.** `non_fast_forward` has no bypass
  actors, so a force push is rejected outright. Get commits right before they
  land.
- An FF push to `main` satisfies every rule in `main integrity` and trips only
  the PR rule, which the owner role always bypasses. It therefore succeeds with
  a `remote: Bypassed rule violations` notice. **That notice is not an error** —
  check the ref-update line before assuming the push failed.

## Terraform

Two stacks live under `terraform/`:

| Stack | State | Purpose |
| --- | --- | --- |
| `bootstrap/` | local | Creates the S3 state bucket. Run once per AWS account. |
| `billing-alarm/` | S3 backend | The alarm stack. |

`bootstrap` keeps local state on purpose: it cannot store state in the bucket it
is creating. First-time setup:

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
terraform -chdir=terraform/bootstrap output backend_hcl   # prints the values below

cd terraform/billing-alarm
cp backend.hcl.example backend.hcl      # gitignored — fill in from the output above
terraform init -backend-config=backend.hcl
```

`bucket` and `region` are account-specific and are passed at init time rather
than committed, because this repository is public.

State locking uses the S3 backend's `use_lockfile`, which locks via S3
conditional writes and requires Terraform 1.10 or newer. There is no DynamoDB
lock table to create or pay for.

The alarm itself must live in **us-east-1**. AWS publishes the `AWS/Billing`
CloudWatch namespace only in that region, regardless of where the resources it
acts on are.

Mocked unit tests prove wiring and typing only. The end-to-end procedure for
checking that the chain actually works against a real account — and the table
recording which claims are still unverified — is
[docs/verifying.md](docs/verifying.md).

Deploy permissions are documented in [docs/permissions.md](docs/permissions.md).
The trap there is the `awscc` provider: it calls the Cloud Control API, so a
principal needs `cloudcontrol:*` **as well as** the underlying service actions.
A policy granting only `cloudwatch:PutMetricAlarm` fails, and so does one
granting only `cloudcontrol:CreateResource`.

## Tooling

```bash
yarn install && yarn prepare
brew install terraform tflint
```

`yarn prepare` installs the lefthook git hooks; `yarn install` alone does not.
Prefer the yarn scripts over calling binaries directly — `yarn prepare`, not
`lefthook install`.

### Git hooks

`lefthook.yml` wires four jobs across three stages. Each is a script under
`shell/hooks/`, so any of them can be run on its own while debugging:

| Stage | Job | What it does |
| --- | --- | --- |
| `pre-commit` | `terraform-fmt` | Formats staged `.tf` files, then exits non-zero if it changed any — so you re-stage instead of committing unformatted HCL. |
| `pre-commit` | `tflint` | `tflint --recursive` when any `.tf` under `terraform/` is staged. |
| `pre-push` | `terraform-validate` | `init -backend=false` plus `validate` for every stack. |
| `commit-msg` | `commitlint` | Conventional Commits, 70-character header, fixed type list. |

Each hook exits 0 immediately when nothing relevant is staged, so unrelated
commits are not slowed down.

Two details in `terraform-validate.sh` are deliberate:

- It points `TF_DATA_DIR` at a scratch directory that is removed on exit. **Do
  not remove this.** Without it the hook re-runs `terraform init -backend=false`
  inside your real `.terraform/`, silently detaching your working copy from the
  remote S3 backend.
- It **discovers** stacks — every immediate subdirectory of `terraform/` holding
  `.tf` files — rather than reading a hardcoded list, which goes stale the first
  time someone adds a stack.

### Commit messages

Conventional Commits, enforced by the `commit-msg` hook and re-checked in CI.
Check a message without committing anything:

```bash
yarn commitlint --verbose < message.txt
```

**Never let a body line begin with `word:`.** Git's trailer parser treats any
line matching `token: value` as the start of the footer, so wrapping prose at 72
columns can produce one by accident:

```text
Rewrite the tooling section to cover all four lefthook jobs and both
workflows, and record the two decisions that are easiest to undo by
accident: the scratch TF_DATA_DIR that stops the pre-push hook from
detaching a working copy from remote state.
```

That `accident:` is read as a footer token mid-paragraph. The footer is then
judged to have no blank line above it and `footer-leading-blank` rejects the
commit — even though there is a perfectly good blank line before the real
`Co-Authored-By` trailer, which is where you will look first. Rewrap the line, or
replace the colon with an em dash.

This is the mirror image of the failure described in `commitlint.config.mjs`:
there, a trailer glued to the body is *not* recognised; here, ordinary prose *is*.

### CI

Both workflows re-run the local checks, because `--no-verify` bypasses the hooks
on commit and push alike.

- `.github/workflows/commitlint.yml` — every commit in the PR range, plus the PR
  title.
- `.github/workflows/terraform.yml` — `fmt`, `tflint`, and `validate` as a matrix
  over each stack.

Three things to preserve:

- In the commitlint workflow the PR title reaches the shell through `env:`, never
  interpolated as `${{ github.event.pull_request.title }}` inside `run:`. A title
  containing `$(...)` would otherwise execute as shell.
- Every action is pinned to an exact patch version. Major tags float, which would
  change what CI enforces without review.
- `terraform init` runs with `-lockfile=readonly`, so a missing platform hash in
  `.terraform.lock.hcl` fails loudly instead of being regenerated on the runner.
  After adding or upgrading a provider, refresh the hashes:

  ```bash
  terraform providers lock \
    -platform=linux_amd64 -platform=darwin_arm64 -platform=darwin_amd64
  ```

## Branch naming

`dev/<github-account-name>/<conventional-commit-type>/<short-summary>`

Example: `dev/bradleyGamiMarques/chore/add-yarn-commitlint-tooling`

## Not yet done

- **No billing alarm.** The backend and provider scaffolding exist, but the
  CloudWatch alarm on `EstimatedCharges` and the stop/terminate action the README
  promises do not.
- **Bootstrap has never been applied.** No state bucket exists in any account
  yet, so `terraform/billing-alarm` cannot be initialised against its backend.
- **No `terraform plan` in CI.** Planning needs real AWS credentials, which means
  an OIDC role and a scoped IAM policy. Until that exists CI covers `fmt`,
  `validate`, and `tflint` only, and the pull request template's **Blast radius**
  section is filled in by hand rather than backed by a plan.
