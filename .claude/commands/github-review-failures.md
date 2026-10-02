---
description: "Use when CI checks are failing on a PR — fetches failure logs, diagnoses root causes, implements fixes, pushes until CI is green."
model: opus
argument-hint: "PR number (e.g., 1690 or #1690)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh run view:*), Bash(git log:*), Bash(git diff:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(crystal:*), Bash(shards:*), Bash(scripts/fetch-cassettes.sh:*), Bash(scripts/release-check:*), Read, Write, Edit, Glob, Grep, Agent
---

# Fix GitHub CI Failures: $ARGUMENTS

Diagnose and fix CI failures. Work systematically: identify failures → read logs → diagnose root cause → fix locally → verify → push.

## Phase 0: Determine the PR

Number → PR. `#N` → strip `#`. Empty → current branch (`gh pr view --json number`).

## Phase 1: Inventory failures

```bash
gh pr checks <PR>
```

For each failing check, get the run id and load the failed logs:

```bash
gh run view <run-id> --log-failed
```

Categorize:
- **Spec failures** — assertion failed, timeout, `ReplayServer#close` raised on an unmatched request
- **Compile failures** — `crystal spec` fails to build (the compiler is the typecheck)
- **Format failures** — `crystal tool format --check` reports files
- **Toolchain install failures** — `crystal-lang/install-crystal` 404 on a stale apt index
- **Cassette fetch failures** — `scripts/fetch-cassettes.sh` could not resolve or download the zazu-ruby tarball
- **Release failures** — `release.yml` tag/version gate, or `gh release create`

## Phase 2: Diagnose

Read the actual error message, not the surrounding noise. The first stacktrace line that points at our code is usually the culprit.

For each failure:

### Reproduce locally

```bash
# Spec
crystal spec spec/zazu/<file>_spec.cr

# Format
crystal tool format --check

# Cassettes
scripts/fetch-cassettes.sh

# Full pipeline
scripts/release-check
```

If you can't reproduce locally, the failure is environmental (CI-only):
- Different Crystal version → CI uses `crystal: latest` (release.yml uses the action default); a new Crystal can change format output or warnings
- Missing cassettes → did `scripts/fetch-cassettes.sh` run before the failing step?
- Race condition → re-running the job fixes it
- Network → external service (cassette tarball download, apt mirrors) hiccup
- `GH_TOKEN` missing → the fetch script falls back to unauthenticated requests, which can be rate limited

### Find the root cause

Apply the five-whys ladder until you reach a fix point that prevents the same class of failure recurring. Don't:

- Disable the failing test
- Skip or weaken the format check
- Cast away a compile error with `.as(...)` / `.not_nil!`
- Edit a cassette or the replay matcher to make a spec pass (cassettes come from zazu-ruby)
- Call a live Zazu/Manza API to "check" a failure

These hide the failure; the underlying bug returns elsewhere.

## Phase 3: Fix and verify

### 3.1 Implement the fix

Touch only what the failure cites, plus what the fix requires.

### 3.2 Run the equivalent local check

The CI step that failed has a local equivalent — run it, get green:

| CI step | Local equivalent |
|---|---|
| `sudo apt-get update -q` + `crystal-lang/install-crystal` | `crystal --version` (install Crystal via your package manager) |
| `scripts/fetch-cassettes.sh` | `scripts/fetch-cassettes.sh` |
| `crystal tool format --check` | `crystal tool format --check` |
| `crystal spec` | `crystal spec` |
| Release gate (tag == `shard.yml` == `Zazu::VERSION`) | `scripts/version` prints the version; `bin/release --dry-run` |

### 3.3 Run the full pipeline

```bash
scripts/release-check
```

### 3.4 Commit + push

```bash
git add <files>
git commit -m "fix(ci): <what was failing>

<root cause and how this addresses it>"
git push origin <branch>
```

Use `fix:` for prod fixes, `chore(ci):` for workflow / config changes.

## Phase 4: Watch the next run

```bash
gh pr checks <PR> --watch
# or
gh run watch <run-id> --exit-status
```

Track until green. If the same step fails again with a different error, repeat. If it fails the same way, your fix is wrong — revert and rethink.

## Phase 5: Verify and document

```bash
gh pr checks <PR>            # all green
gh pr view <PR> --json mergeable,reviewDecision
```

If the failure was CI-config drift (workflow YAML out of sync with reality), also update relevant docs:
- `shard.yml` `crystal:` constraint
- `CLAUDE.md` if a convention changed

## Common patterns and fixes

### `install-crystal` fails with a 404 (libevent or similar)

The runner image's apt index is stale after Ubuntu republished a package, and `install-crystal` installs with `--no-upgrade`. `ci.yml` and `release.yml` run `sudo apt-get update -q` before it. Keep that step; if a new workflow installs Crystal, add it there too. Re-running the job also fixes a one-off.

### Cassette replay says "no cassette interaction matches"

The recorded request shape drifted from what the SDK now sends, or two cassettes sharing method + URI were loaded in one spec (`authorize` vs `authorize_same_key`, `create` vs `create_duplicate`: load one per spec). Either:
- Fix the SDK's request to match the cassette (the cassette is the contract)
- If the wire format really changed, record new cassettes in zazu-ruby and ship a new release; never record or edit them here

### `missing cassette ... (run scripts/fetch-cassettes.sh first)`

The fetch step did not run or the tarball is older than the specs. `scripts/fetch-cassettes.sh` takes the newest zazu-ruby `v*` tag; a spec that needs a newer cassette waits on that zazu-ruby release.

### Cassette fetch fails with 404 or 5xx

The tag resolves through `git ls-remote`, the tarball through `releases/download/<tag>/cassettes-<tag>.tar.gz` (retried 8 times). A 404 means the newest zazu-ruby tag has no tarball asset yet (its release workflow is still running or failed): re-run later or pin a tag, `scripts/fetch-cassettes.sh v0.3.0`.

### Release: "Tag ... does not match shard.yml version" / "src/zazu.cr does not carry ..."

The tag was pushed by hand or `scripts/version` drifted. Releases go through `bin/release`, which writes both `shard.yml` and `Zazu::VERSION` via `scripts/version`. Don't edit `bin/release` in place.

## Karpathy guidelines

- **Think before coding** — read the actual error, don't pattern-match on the first guess.
- **Goal-driven execution** — the green CI check is the verification.
- **Surgical changes** — fix the failing class of error, not adjacent things.
