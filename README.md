## 🦎 Lizard
[![Terraform](https://img.shields.io/badge/Terraform-844FBA?logo=terraform&logoColor=fff)](#)
![Yarn](https://img.shields.io/badge/yarn-%232C8EBB.svg?style=for-the-badge&logo=yarn&logoColor=white)
## 🌟 Highlights
- Lizard provides IaC to stop or terminate AWS resources when billing amounts go over a predefined threshold in CloudWatch Alarms.

## 🔥✍🏾 Authors

- Bradley Andrew Marques

## 🎯 Purpose
- This project was created to provide ease of mind for AWS customers due to the Production AWS Cost and Billing bug dated `2026-07-17` that saw accounts billing estimates being in the billions or trillions of dollars.
- The goal is to provide IaC that can be modified for your personal, business, or enterprise AWS Account to stop or terminate resources automatically once a Cloudwatch alarm enters the ALARM state.

## 🚀 Getting Started
1. Clone the repository to your development machine
2. Grant your deploying identity the permissions in [docs/permissions.md](docs/permissions.md)
3. Enable **Receive CloudWatch Billing Alerts** in the payer account — without it AWS publishes no billing data and no alarm can ever fire
4. Deploy the configurations to your AWS account via Terraform

## 🤝 Contributing
Thank you for contributing to Lizard!
Follow these steps to ensure a smooth Pull Request process

1. Install the local tooling:

   ```sh
   yarn install && yarn prepare
   ```

   `yarn install` pulls in commitlint, and `yarn prepare` installs the git hooks that lint your commit messages. `yarn install` alone does **not** install the hooks — run both.

   Requires [lefthook](https://lefthook.dev/install/) on your PATH (`brew install lefthook`). Yarn resolves to the pinned 4.x release via corepack.

2. PR titles should follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), e.g.:

   `feat(infra): add CloudFormation IaC`

   Allowed types: `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test`

3. As part of the Pull Request process update this README.md file under the Authors heading with the name you would like to be credited under.
4. Branches should follow the pattern of `dev/<github-account-name>/<conventional-commits-action>/<summary>`
5. PR's should fill out the pull request template — GitHub pre-fills it from `.github/pull_request_template.md` when you open a PR.
6. My preference is that all commits are verified and that we keep linear commit history.
<img width="1200" height="630" alt="image" src="https://github.com/user-attachments/assets/25d8e971-03d8-4b81-95e1-c9269c878c2a" />
