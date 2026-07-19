<!--
  Thanks for contributing to Lizard!

  PR titles should follow Conventional Commits, e.g.:
    feat(infra): add billing alarm module
    fix(alarm): handle missing threshold variable
  Allowed types: build, chore, ci, docs, feat, fix, perf, refactor,
  revert, style, test.
-->

## Summary

<!-- What does this PR do, and why? Keep it concise. -->

## Related issues

<!-- Link issues this PR closes or relates to, e.g. "Closes #123". -->

## Changes

<!-- Bullet the notable changes so reviewers know where to look. -->

-
-

## Blast radius

<!--
  Lizard stops and terminates real AWS resources. Spell out what this PR
  changes about that behaviour: which resources become eligible for stop or
  terminate, which alarms or thresholds move, and what happens on a
  false-positive alarm. Write "None — no change to stop/terminate behaviour"
  if that is the case.
-->

## How was this tested?

<!--
  Include the commands you ran and their results. For infrastructure changes,
  paste the relevant `terraform plan` output — redact account IDs and ARNs —
  so reviewers can see exactly what would be created, changed, or destroyed.
-->

-

## Checklist

- [ ] PR title follows [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] `terraform fmt -check -recursive` and `terraform validate` pass locally
- [ ] `terraform plan` reviewed — no unintended `destroy` or `replace` in the output
- [ ] Updated documentation where relevant (README, variable descriptions, comments)
- [ ] No secrets, credentials, account IDs, or ARNs committed
- [ ] Added my name to the Authors section of the README
- [ ] Commits are verified and the branch is rebased on `main` for linear history

## Notes for reviewers

<!-- Anything reviewers should pay special attention to, or context that isn't obvious from the diff. Delete if not needed. -->
