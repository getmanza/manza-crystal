---
description: "Executes full autonomous engineering workflow with verification. Use when implementing complete features, tackling GitHub issues, or running end-to-end development cycles."
model: opus
argument-hint: "GitHub issue number/URL or feature description"
allowed-tools: Bash(gh issue view:*), Bash(gh search:*), Bash(gh issue list:*), Bash(gh pr create:*), Bash(gh pr view:*), Bash(crystal:*), Bash(shards:*), Bash(scripts/fetch-cassettes.sh:*), Bash(scripts/release-check:*), Bash(git:*), Read, Write, Edit, Glob, Grep, Agent, TaskCreate, TaskUpdate, TaskList
---

# LFG — full autonomous workflow

Execute a complete engineering workflow with verification at each phase. The phases below exist because skipping any one of them has caused a production bug at least once — the checklist is load-bearing.

## Phase 0: Branch setup

1. `git branch --show-current`
2. If not on `main`: `git checkout main`
3. `git pull origin main`
4. `git checkout -b issue-{number}-{brief-description}` (or `feature/{description}` if no issue)

## Phase 1: Understand

If `$ARGUMENTS` is a GitHub issue number/URL:

```bash
gh issue view <number> --json title,body,labels,assignees,comments
```

Define explicit acceptance criteria (GIVEN / WHEN / THEN). Don't proceed until you can articulate them.

**Comprehension gate** — answer all five before writing code:

1. State the problem in one sentence.
2. Why is it needed?
3. What changes from the user's perspective?
4. What edge cases aren't explicit?
5. What data flow / code path is involved?

Use `TaskCreate` to record steps; update as you go.

## Phase 2: Explore

1. Find related files (Glob/Grep, or the Explore agent, `model: haiku`, for broad searches).
2. Read existing patterns in similar features.
3. Understand dependencies and integration points.
4. Check existing test coverage.

## Phase 3: Plan

1. List files to modify with specific changes.
2. List new files to create with their purpose.
3. Plan test coverage (tests first).
4. Update the task list.

## Phase 4: Implement (TDD)

For each logical unit:

### 4.1 Failing test first

Create a test that demonstrates the expected behavior. Confirm it fails for the right reason:

```bash
crystal spec spec/manza/<file>_spec.cr
```

### 4.2 Minimum implementation

Project conventions:

| Use | Instead of |
|-----|-----------|
| `Manza::Client` resources (`client.transfer_drafts.create(...)`) | hand-rolled `HTTP::Client` calls |
| `Resources::Base` helpers (`http_get`/`http_post`/..., `list_page`) | calling `client.request` from a resource |
| `encode_path("api/x", id)` | interpolating IDs into URL strings |
| `Manza::Page` (`#next`, `MAX_PER_PAGE`) | manual cursor loop |
| `Manza::Error#kind`, `Manza::ConflictError#payment_id` | status-code or message matching |
| snake_case `JSON::Any` bodies as-is | auto-camelCasing, typed models |
| `crystal spec` | other test frameworks |
| `crystal tool format` | manual formatting |
| `with_replay("resource/cassette")` from `spec/spec_helper.cr` (one cassette per spec) | `with_stub` for anything a cassette covers, or hand-mocked servers |
| `fixture_id("MANZA_FIXTURE_X")` from `spec/support/fixture_ids.cr` | literal IDs in specs |

**Never call a live Manza API** from specs, scripts or this session. Specs replay manza-ruby's cassettes (`scripts/fetch-cassettes.sh`) only; live staging calls create real transfers and approval requests for the team, and only manza-ruby records cassettes. A change that needs a new or changed cassette is a manza-ruby change first: stop and say so.

### 4.3 Refactor

Once green, refactor with tests still passing.

### 4.4 Validate

```bash
crystal tool format   # auto-apply formatting
crystal spec          # full suite (the compiler is the typecheck)
```

### 4.5 Repeat

Move to the next unit. Mark task items complete as you finish them.

## Phase 5: Deep root-cause analysis (bug fixes only)

For bug fixes, investigate before implementing:

- **Trace the data lifecycle** — where was the value created, how did it reach the failure point, what assumption broke?
- **Use git history** — `git log --oneline -20 <file>`, `git blame <file>`. Was a guard there before? Why was it removed/added?
- **Map callers** — grep for callers of the failing function; does the bug only show up in one context?
- **Five whys** — keep asking "why" until you reach a meaningful fix point.

**Fix-location principle**: the best fix is rarely where the error is raised. Ask "where is the earliest point I could prevent this error?" Fix there.

**Superficial fixes to avoid**:
- `try` / `|| default` chaining without understanding why the value is `nil`
- `rescue` that swallows the error
- Changing `raise` paths to silent `nil` returns
- `.as(Foo)` / `.not_nil!` casts instead of fixing the producer

## Phase 6: Verify

All must pass before committing:

```bash
scripts/fetch-cassettes.sh           # cassettes present and current
crystal tool format --check          # CI gate
crystal spec                         # all green (compiles the library, so it is the typecheck)
```

Re-read the original requirements: would the requester consider this fully resolved? Have you addressed the root cause? Do the tests prove the fix?

## Phase 6.5: Fable validation

Spawn the `fable-validator` agent (it is pinned to Fable) with the issue, the acceptance criteria from Phase 1 and the base branch. On **BLOCK**, fix every blocker (back to Phase 4 for code, with a failing test first), re-verify, and run the validator again. On **PASS WITH NOTES**, fix the risks you agree with and list the rest in the pull request under "Accepted risks". If those fixes change the diff, re-verify and run the validator again. Put the validator's one-line verdict and its "Not verified" list in the pull request body. Do not open the pull request before a PASS or PASS WITH NOTES.

## Phase 7: Commit and PR

**Backticks in PR bodies pass through `<<'EOF'` heredocs verbatim — do NOT escape them with `` \` ``.** See the "PR descriptions" section in `CLAUDE.md`.

```bash
git add <specific_files>
git commit -m "$(cat <<'EOF'
feat(scope): brief description

## Summary
[What changed and why]

## Test Coverage
- spec 1: validates requirement X
- spec 2: validates edge case Y

## Verification
- [x] crystal tool format --check
- [x] crystal spec
EOF
)"

git push -u origin $(git branch --show-current)

gh pr create --title "feat(scope): brief description" --body "$(cat <<'EOF'
## Summary
- Key change 1 — uses `Manza::Page` from the SDK
- Key change 2

Closes #<issue_number>

## Fable validation
Verdict: <PASS | PASS WITH NOTES>. Not verified: <list>.

## Accepted risks
<risks from the validator you did not fix, or "none">

## Test plan
- [ ] Scenario 1
- [ ] Scenario 2
EOF
)"
```

If you typed `` \` `` anywhere in the body, delete the backslash. The single-quoted EOF delimiter is doing all the shell-escaping work.

## Verification checklist

- [ ] All acceptance criteria met.
- [ ] Tests written before implementation.
- [ ] `crystal tool format --check` passes.
- [ ] `crystal spec` passes.
- [ ] No live API call was made; replay only.
- [ ] No hand-rolled HTTP — uses the SDK's `Resources::Base` helpers.
- [ ] `fable-validator` verdict is PASS or PASS WITH NOTES (Phase 6.5), and it is in the PR body.
- [ ] Accepted risks (if any) are listed in the PR body.
- [ ] PR created with description.

## Karpathy guidelines (always)

These reduce common LLM coding mistakes. Apply on every change, not just LFG runs:

1. **Think before coding** — surface assumptions, push back on overcomplication, ask when unclear.
2. **Simplicity first** — minimum code that solves the problem, no speculative abstractions.
3. **Surgical changes** — touch only what you must; clean up your own orphans, not pre-existing dead code.
4. **Goal-driven execution** — define success criteria as a verifiable test, loop until verified.
