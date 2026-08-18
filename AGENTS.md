# AGENTS.md

## PR Workflow

When creating or updating a PR from `dev` to `main`:

1. **Always run `git fetch origin main` first** — This is critical. The local `main` branch is often outdated and will show stale committed changes as part of the diff if not refreshed.
2. Compare `origin/main..dev` to identify only the actual new changes.
3. Check if a PR already exists (use `github_list_pull_requests`).
4. If none exists, create one with an accurate title and description summarizing the changes.
5. If one exists, update its title and description to reflect the actual current diff.
