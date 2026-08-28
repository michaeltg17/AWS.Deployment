# AGENTS.md

## Context

- `ARCH.md` documents the full architecture and workflows (Terraform + EKS +
  ALB controller + k8s deploy/CD + teardown). Read it for context before
  working on deployment, teardown, CI/CD, or anything that crosses the
  Terraform / k8s / AWS boundary.

## Branching model

- **All work happens on the `dev` branch.** Commit directly to `dev`; do **not** create feature/topic branches that open a PR straight to `main`.
- `main` only ever changes via a merged **`dev` → `main`** PR. There is exactly one PR in flight at a time, from `dev` to `main`.
- So the loop is: commit on `dev` → push `dev` → open (or update) the `dev` → `main` PR → merge.

## PR Workflow (dev → main)

When creating or updating the `dev` → `main` PR:

1. **Always run `git fetch origin main` first** — This is critical. The local `main` branch is often outdated and will show stale committed changes as part of the diff if not refreshed.
2. Compare `origin/main..dev` to identify only the actual new changes.
3. Check if a PR already exists (use `github_list_pull_requests`).
4. If none exists, create one with an accurate title and description summarizing the changes.
5. If one exists, update its title and description to reflect the actual current diff.
