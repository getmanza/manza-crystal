---
description: "Use when a PR has unresolved review comments — evaluates each, implements valid fixes minimally, pushes back on incorrect suggestions, resolves threads."
model: opus
argument-hint: "PR number (e.g., 1690 or #1690)"
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh pr comment:*), Bash(gh api:*), Bash(git log:*), Bash(git blame:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(crystal:*), Bash(shards:*), Bash(scripts/fetch-cassettes.sh:*), Bash(scripts/release-check:*), Read, Write, Edit, Glob, Grep, Agent
---

# Review GitHub PR Comments: $ARGUMENTS

Evaluate each comment against the actual codebase before accepting. The reviewer might be right, partially right, or wrong; treat every finding as a hypothesis to verify.

## Phase 0: Determine the PR

Number → PR. `#N` → strip `#`. Empty → current branch (`gh pr view --json number`).

## Phase 1: Inventory comments

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments \
  --jq '.[] | {id, user: .user.login, path, line, body}'
```

Group by:
- **Reviewer** (CodeRabbit, human, etc.) — different reviewers warrant different push-back thresholds.
- **Severity** if the reviewer marks it (CodeRabbit uses 🔴/🟡/🟢; humans usually don't).
- **File** — batch fixes by file to minimize merge-risk.

## Phase 2: Per-comment workflow

For each comment:

### 2.1 Verify the finding

1. Read the file at the cited line **right now**. Don't trust the diff — main may have moved.
2. Read 5 lines above and below for context.
3. If the comment references a commit sha, check whether HEAD has already addressed it.

### 2.2 Decide

- **Valid + actionable** → fix.
- **Valid but wrong fix proposed** → fix differently, explain in the reply.
- **Invalid** (suggestion conflicts with conventions, breaks tests, hurts performance) → push back.
- **Stale** (already fixed) → reply with the sha that fixed it.

Verification ladder before accepting any "valid" judgment:
1. Does the cited code still exist as described?
2. Does the suggestion fix something a test would catch?
3. Does it conflict with `CLAUDE.md` conventions?
4. Would a senior engineer call this overcomplicated? (Karpathy #2)

### 2.3 Implement minimally

- Touch only the cited lines and what the fix requires.
- Don't refactor adjacent code.
- Match existing style even if you'd write it differently.
- If the fix surfaces a bigger issue, mention it but don't pull on the thread.

### 2.4 Verify locally

```bash
crystal tool format --check
crystal spec
```

If anything regresses, the fix is wrong. Try a different approach or push back.

### 2.5 Reply on the thread

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments/<comment-id>/replies \
  -f body='<reply>'
```

**Reply templates**:

- **Fixed**: "Fixed in `<sha>`. <one-line summary>."
- **Pushed back**: "Disagree — <reasoning>. <reference to CLAUDE.md / test / docs>. Leaving as-is."
- **Stale**: "Already handled in `<sha>`."
- **Partial**: "Addressed `<part>` in `<sha>`; deferring `<part>` because <reason>."

Reply on the thread, not as a new comment, so the conversation collapses cleanly.

## Phase 3: Commit batching

Group commits by theme, one commit per logical change:

```bash
git add <files>
git commit -m "fix(area): <one-line summary>

Addresses CodeRabbit feedback on PR #<N>:
- <comment 1 summary>
- <comment 2 summary>"

git push origin <branch>
```

Don't squash unrelated CodeRabbit findings into a single mega-commit — when one regresses, you want to revert one commit, not all of them.

## Phase 4: Verify all threads resolved

```bash
gh api repos/{owner}/{repo}/pulls/<PR>/comments \
  --jq '.[] | select(.in_reply_to_id == null) | {id, body: .body[:80]}'
```

Each top-level comment should have a reply. Anything missing → reply now.

```bash
gh pr checks <PR>            # CI green after the new commits?
```

## Karpathy guidelines

Especially relevant here:
- **Think before coding** — verify the finding before reaching for the fix.
- **Surgical changes** — only the cited lines.
- **Goal-driven execution** — every fix has a verification step (`crystal tool format --check` and `crystal spec`).
