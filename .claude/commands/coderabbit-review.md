---
description: "Address CodeRabbit feedback on a PR. Verify each finding against current code, fix only still-valid issues, skip the rest with a brief reason, keep changes minimal, and validate."
model: opus
argument-hint: "PR number (e.g., 1690 or #1690)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(git log:*), Bash(git blame:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(crystal:*), Bash(shards:*), Bash(scripts/fetch-cassettes.sh:*), Bash(scripts/release-check:*), Read, Write, Edit, Glob, Grep, Agent
---

# Address CodeRabbit Findings: $ARGUMENTS

CodeRabbit produces many findings per PR. Some are real bugs, many are stylistic, some are stale (the code already moved on), and a few are wrong (CodeRabbit doesn't know our conventions).

The job: **verify each finding against current code, fix only still-valid issues, skip the rest with a brief reason, keep changes minimal, and validate.**

This is a thin wrapper over `/github-review-comments` that pre-filters to CodeRabbit's bot user and biases toward push-back over compliance. CodeRabbit is a useful second pair of eyes, not a style authority.

## Phase 0: Determine the PR

Number → PR. `#N` → strip `#`. Empty → current branch (`gh pr view --json number`).

## Phase 1: Pull CodeRabbit findings

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments \
  --jq '.[] | select(.user.login == "coderabbitai[bot]") | {id, path, line, body}'
```

CodeRabbit comments include severity markers (`🔴 Critical`, `🟡 Minor`, `🟢 Nitpick`, `⚡ Quick win`). Sort by severity — critical first, nitpicks last.

## Phase 2: Per-finding workflow

For each finding:

### 2.1 Read the actual code

```bash
# What the file looks like RIGHT NOW, not what CodeRabbit saw:
sed -n '<start>,<end>p' <path>
```

CodeRabbit comments persist across force-pushes. The cited line might already have been changed.

### 2.2 Verify the finding is still valid

A finding is **valid** when all four hold:

1. The cited code still exists as described.
2. The issue would fail a test, block a build, or cause a real bug — not just a style preference.
3. The fix doesn't conflict with `CLAUDE.md` conventions.
4. The fix is minimal — touches the cited lines and the immediate fix scope, nothing else.

A finding is **invalid / skip-with-reason** when any of:

- The code has already been changed.
- The "issue" is a stylistic preference `crystal tool format` doesn't enforce.
- The suggested fix is more complex than the original code.
- The suggested fix would break a documented convention or test.
- The suggestion treats a symptom while we already handle the root cause elsewhere.

### 2.3 Apply

**Valid** → fix minimally:

- Don't refactor adjacent code.
- Don't "improve" formatting `crystal tool format --check` already passed.
- Verify with `crystal tool format --check` and `crystal spec` after each fix.

**Invalid** → skip with a reason in the reply.

### 2.4 Reply on the thread

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments/<comment-id>/replies \
  -f body='<reply>'
```

**Reply templates** (be specific — vague replies make CodeRabbit re-flag the same thing later):

- **Fixed**: "Fixed in `<sha>`. <one-line summary>."
- **Skipped — already addressed**: "Already handled in `<sha>` (HEAD shows `<line>`)."
- **Skipped — convention**: "Disagree — our convention is `<X>`, see `CLAUDE.md` § `<Y>`. Leaving as-is."
- **Skipped — out of scope**: "Out of scope for this PR. Tracked separately as `<issue/note>`."
- **Skipped — stylistic**: "The formatter already covers what we want; this would add complexity for no behavior change."
- **Partial**: "Addressed `<part>` in `<sha>`; deferring `<part>` because <reason>."

## Phase 3: Commit + push

Group commits by theme, conventional-commit prefixes:

```bash
git add <files>
git commit -m "fix(<scope>): <one-line summary>

Addresses CodeRabbit feedback on PR #<N>:
- <finding 1 summary>
- <finding 2 summary>"

git push origin <branch>
```

One commit per theme. Don't squash unrelated findings — when one regresses, you want to revert one commit, not all of them.

## Phase 4: Verify

```bash
crystal tool format --check  # local verification before pushing
crystal spec
gh pr checks <PR> --watch    # CI green after the new commits
```

Confirm every CodeRabbit thread has a reply:

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments \
  --jq '.[] | select(.user.login == "coderabbitai[bot]") | select(.in_reply_to_id == null) | {id, body: .body[:80]}'
```

## When to push back hard

CodeRabbit doesn't know:
- The Karpathy guidelines we follow (no speculative abstractions, surgical changes).
- Our snake_case wire format decision — it sometimes suggests camelCasing or typed models.
- That the SDK is the canonical implementation — sometimes it suggests "improvements" the SDK already handles.
- The cassette-replay contract — it might suggest mocking that breaks parity with the Ruby SDK.
- That specs never call a live API — it might suggest hitting staging or recording cassettes here; only zazu-ruby records them.

When CodeRabbit suggests something that would violate one of these, push back with a one-line explanation. Don't capitulate to keep the PR quiet.

## Karpathy guidelines

Especially relevant:
- **Think before coding** — verify before fixing.
- **Simplicity first** — reject suggestions that add complexity for marginal gain.
- **Surgical changes** — only what the comment cites.
