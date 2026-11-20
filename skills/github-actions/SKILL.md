---
name: github-actions
description: "GitHub Actions best practices: job naming, workflow structure, caching, matrix, and bots. Use when creating or editing a GitHub Actions workflow, setting up CI/CD, or choosing bots for a repo."
---

# GitHub Actions

## Job naming
- lowercase with hyphens: `lint`, `typecheck`, `test`, `build`, `security-scan`
- Name describes what the job does, not `job1`

## Workflow structure
- Separate workflows: `ci.yml` (PR), `cd.yml` (merge), `release.yml` (tag)
- Jobs: `lint` → `typecheck` → `test` (matrix) → `build` → `security-scan`
- Use `concurrency` group to cancel stale runs
- Use `actions/cache` for dependencies
- Use `matrix` for multiple versions/OS

## Bots
- **Dependabot / Renovate**: dependency updates
- **CodeQL**: security scanning
- **Stale bot**: cleanup issues/PRs
- **Auto-merge bot**: merge when checks pass

## Gotchas
- `actions/checkout` defaults to shallow clone; set `fetch-depth: 0` if history needed
- Secrets are not available in fork PRs by default
- `GITHUB_TOKEN` has limited scope; use PAT for cross-repo access