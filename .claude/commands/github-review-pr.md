---
description: "Use when a PR needs full review — fixes CI failures first, then addresses unresolved review comments. Run failures first because comment fixes trigger new CI runs that obscure the original failures."
model: opus
argument-hint: "PR number (e.g., 1690 or #1690)"
allowed-tools: Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh pr comment:*), Bash(gh api:*), Bash(gh run view:*), Bash(git log:*), Bash(git blame:*), Bash(git diff:*), Bash(git push:*), Bash(git commit:*), Bash(git add:*), Bash(crystal:*), Bash(shards:*), Bash(scripts/fetch-cassettes.sh:*), Bash(scripts/release-check:*), Read, Write, Edit, Glob, Grep, Agent
---

# Review GitHub PR (full pass): $ARGUMENTS

Run a full review pass in two phases, in this order:

1. **Phase A: CI failures** — fix anything red before touching review comments.
2. **Phase B: Unresolved review comments** — evaluate, fix valid ones, push back on incorrect suggestions, resolve all threads.

Reverse order is wrong: comment fixes push new commits that retrigger CI, masking the original failure signal.

## Phase 0: Determine the PR

If `$ARGUMENTS` is a number → that PR. If it's `#N` → strip the `#`. If empty → use the current branch's PR (`gh pr view --json number`).

## Phase A: CI failures

```bash
gh pr checks <PR>
```

For each failing check:

1. `gh run view <run-id> --log-failed` — get the actual error
2. Reproduce locally:
   - Test or compile failure → `crystal spec spec/manza/<file>_spec.cr` (the compiler is the typecheck)
   - Format failure → `crystal tool format --check` (fix with `crystal tool format`)
   - Missing cassette → `scripts/fetch-cassettes.sh`
3. Fix the root cause. Don't:
   - Disable the failing test
   - Skip the formatter check
   - Cast types (`.as`, `.not_nil!`) to bypass the compiler
4. Verify locally: `scripts/release-check` (shards install, fetch cassettes, format check, spec)
5. Commit with conventional-commit prefix (`fix:`, `test:`, `chore:`)
6. Push: `git push origin <branch>`
7. Wait for the new run: `gh pr checks <PR> --watch`

Repeat until all checks are green.

## Phase B: Unresolved review comments

The REST endpoint `pulls/<N>/comments` returns every review comment with no resolution state. We want **only unresolved threads** — use GraphQL's `reviewThreads.isResolved`:

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 1) {
            nodes {
              databaseId
              author { login }
              body
            }
          }
        }
      }
    }
  }
}' -F owner=<owner> -F repo=<repo> -F number=<PR> \
  --jq '.data.repository.pullRequest.reviewThreads.nodes | map(select(.isResolved == false)) | map({thread_id: .id, comment_id: .comments.nodes[0].databaseId, path, line, author: .comments.nodes[0].author.login, body: (.comments.nodes[0].body | .[:300])})'
```

The `thread_id` (GraphQL node id, looks like `PRRT_…`) is what you need to mark a thread resolved later. The `comment_id` (numeric `databaseId`) is what the REST `pulls/comments/<id>/replies` endpoint expects when posting a reply.

For each unresolved thread:

1. **Read the actual code at the cited line** — don't assume the comment is current. Codebase may have moved on.
2. **Evaluate against project conventions** in `CLAUDE.md`. If the suggestion conflicts with documented conventions, push back.
3. **Decide**: valid issue → fix. Invalid suggestion → reply with reasoning. Already addressed → reply with the commit sha.
4. **Implement valid fixes minimally**:
   - Touch only the cited line(s) plus what the fix requires
   - Don't rewrite adjacent code
   - Match existing style
5. **Reply on the comment thread** (not as a new top-level comment):

   ```bash
   gh api repos/{owner}/{repo}/pulls/<PR>/comments/<comment_id>/replies \
     -f body='<reply>'
   ```

   Optionally mark the thread resolved when the work is committed:

   ```bash
   gh api graphql -f query='
   mutation($id: ID!) {
     resolveReviewThread(input: { threadId: $id }) {
       thread { isResolved }
     }
   }' -F id=<thread_id>
   ```

6. **Verify** after each batch of fixes: `scripts/release-check` (shards install, fetch cassettes, format check, spec)
7. **Commit + push** in batches grouped by topic (one commit per CodeRabbit theme is fine).

## Order of comment batches

Evaluate findings in this order so cheap fixes ship first:

1. **Real bugs** — wrong behavior, missing edge case, security issue. Fix immediately.
2. **Type-safety issues** — compiler warnings, unhandled error paths (`rescue` that swallows).
3. **Style / lint** — only fix if `crystal tool format` doesn't auto-fix.
4. **Suggestions / nits** — accept if the author has earned trust; push back if it adds complexity for no gain.

## Reply templates

**Accepted + fixed**:
> Fixed in `<sha>`. <one-sentence summary of the change>.

**Pushed back**:
> Disagree — <reasoning>. <link to convention or test that justifies>. Leaving as-is.

**Already addressed**:
> Already handled in `<sha>` (earlier in this PR / on main).

## Final verification

```bash
gh pr checks <PR>            # all green
gh pr view <PR> --json reviewDecision
```

If `reviewDecision` is `CHANGES_REQUESTED`, ask the reviewer to re-review.

## Karpathy guidelines

Apply always. Specifically here:
- **Surgical changes** — only touch what the comment cites.
- **Surface tradeoffs** — if the reviewer's suggestion has a downside, name it before applying.
