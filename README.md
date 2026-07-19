## 🦎 Lizard
[![Terraform](https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=fff)](#)
![Yarn](https://img.shields.io/badge/yarn-%232C8EBB.svg?style=for-the-badge&logo=yarn&logoColor=white)

## 🌟 Highlights
- Lizard provides example IaC to stop or terminate AWS resources when billing amounts go over a predefined threshold in CloudWatch Alarms.
- A CloudWatch alarm watches estimated charges. When it fires, EventBridge starts
an SSM Automation runbook that stops every running EC2 instance carrying the tag
`StoppableBy=Lizard`.

## 🎯 Purpose
Built after the AWS Cost and Billing bug of `2026-07-17`, which showed accounts
estimates in the billions. The goal is a circuit breaker you can leave running:
spend crosses a line, and the resources you nominated stop.

## ⚠️ Know the blast radius

**Lizard cannot tell which instance caused the spend.** A billing alarm reports
that a service went over; it carries no instance identity. You nominate what is
expendable by tagging it.

- An untagged instance burning money **will not be stopped**
- **Every** tagged instance stops, not just the expensive one
- Instances are stopped, never terminated

The tag is enforced in IAM, not just in the runbook, so an untagged instance
cannot be stopped even if the runbook is wrong.

## 🚀 Getting started

See **[docs/deploying.md](docs/deploying.md)** — prerequisites, the IAM policy,
deployment, and how to verify it works.

Two things that catch people out: billing metrics exist only in **us-east-1**,
and they are published only if **Receive CloudWatch Billing Alerts** is enabled
in the payer account.

## 🔥✍🏾 Authors

- Bradley Andrew Marques

## 🤝 Contributing

1. Install the tooling — both commands, `yarn install` alone does not install the
   git hooks:

   ```sh
   yarn install && yarn prepare
   ```

   Requires [lefthook](https://lefthook.dev/install/) and `terraform` on your
   PATH (`brew install lefthook terraform tflint`).

2. Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
   Allowed types: `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test`
3. Branches: `dev/<github-account-name>/<conventional-commit-type>/<summary>`
4. Add yourself under Authors above.
5. Commits should be verified, and history stays linear.

Maintainer notes — merge workflow, AWS gotchas, module internals — are in
[CLAUDE.md](CLAUDE.md).

<img width="1200" height="630" alt="image" src="https://github.com/user-attachments/assets/25d8e971-03d8-4b81-95e1-c9269c878c2a" />
