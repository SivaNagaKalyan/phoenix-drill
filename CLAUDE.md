# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

Phoenix Drill: an automated disaster recovery test. It builds a small stateful system on a
disposable Kubernetes cluster, backs it up to storage outside the cluster, deletes the cluster,
rebuilds everything from code, and proves the data survived with a checksum. See README.md.

## House rules

* Never use em dashes or en dashes in any file, commit message, or reply. Use commas, colons,
  parentheses, or separate sentences. CI fails on em dashes.
* Every script is idempotent, uses `set -Eeuo pipefail` via `scripts/lib.sh`, and passes shellcheck.
* Pin every tool and image in `tools/versions.env`. Never use `latest`.
* Kubernetes workloads must pass the `restricted` Pod Security Standard.
* Never commit secrets. Runtime state lives in `.phoenix/` (git-ignored).
* Numbers in docs must come from real drill runs, never invented.

## Commands

```bash
make tools      # install pinned kind, kubectl, kubeconform
make lint       # shellcheck, yamllint, ruff, kubeconform, hadolint
make test       # unit tests; set TEST_DATABASE_URL for integration tests
make phoenix    # the full drill (needs docker)
make down       # remove everything
```

## Running the drill and fixing failures

The repository lives at https://github.com/SivaNagaKalyan/phoenix-drill.

1. `gh auth status` must succeed. If it does not, stop and ask the user to run `gh auth login`
   themselves. Never handle tokens or passwords.
2. Trigger the drill: `gh workflow run phoenix.yml --ref main`, then follow it with
   `gh run watch "$(gh run list --workflow phoenix.yml --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status`.
3. If it fails, download the artifact (`gh run download`), read `.phoenix/diagnostics/`, fix the
   root cause, commit, push, and rerun. Repeat until green.
4. Report the numbers from the run summary (RTO, data loss window, records verified) to the user.
