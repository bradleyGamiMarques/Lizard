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

```bash
gh pr view <n> --json state --jq .state     # want MERGED
git switch main && git pull
git branch -d <branch>                      # -d, not -D: refuses if not merged
git push origin --delete <branch>           # only if it survived the merge
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

## Tooling

```bash
yarn install && yarn prepare
```

`yarn prepare` installs the lefthook git hooks; `yarn install` alone does not.
Prefer the yarn scripts over calling binaries directly — `yarn prepare`, not
`lefthook install`.

- **commitlint** (`commitlint.config.mjs`) enforces Conventional Commits with a
  70-character header limit and a fixed type list.
- **lefthook** (`lefthook.yml`) runs commitlint on `commit-msg`.
- **CI** (`.github/workflows/commitlint.yml`) lints every commit in the PR range
  and the PR title, because `git commit --no-verify` bypasses the local hook.

In that workflow the PR title reaches the shell through `env:`, never
interpolated as `${{ github.event.pull_request.title }}` inside `run:`. A title
containing `$(...)` would otherwise execute as shell. Keep it that way.

## Branch naming

`dev/<github-account-name>/<conventional-commit-type>/<short-summary>`

Example: `dev/bradleyGamiMarques/chore/add-yarn-commitlint-tooling`

## Not yet done

- **No Terraform.** The README describes billing-alarm IaC that does not exist
  yet.
- **No Terraform CI.** `terraform validate` fails when there are no `.tf` files,
  so `fmt -check` / `validate` / `plan` should land with the first real config.
  That is also what turns the pull request template's **Blast radius** section
  from a prompt into an enforced check.
- **Unverified:** whether `delete_branch_on_merge` fires for merges detected
  from an FF push rather than performed by the merge button. If a branch
  survives the next merge, delete it with
  `git push origin --delete <branch>`.
