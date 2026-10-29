# manza-crystal

Crystal SDK for the Manza API. It **replays manza-ruby's cassettes** in its own spec harness. manza-ruby is the reference implementation: it records cassettes, ships them as a release tarball, and every other SDK (manza-ts, manza-crystal, ...) proves wire-format parity by replaying them.

## Stack

| Concern | Tool | Notes |
|---|---|---|
| Language | Crystal, `crystal: ">= 1.10.0"` | `shard.yml`. CI runs `crystal: latest` (single version, no matrix) |
| HTTP | stdlib `HTTP::Client` | `src/manza/client.cr`. No shard dependencies |
| Test runner | `crystal spec` | `spec/` |
| Cassette replay (tests) | Stdlib `HTTP::Server` + YAML | `spec/support/replay_server.cr` reads manza-ruby's VCR YAML. `spec/support/stub_server.cr` is for non-cassette cases |
| Format | `crystal tool format` | CI runs `--check`. No separate linter or typecheck step: the compiler is the typecheck |
| Package registry | None | Shards install straight from git tags (`github: getmanza/manza-crystal`) |
| Release | `bin/release` | manza SDK release kit (byte-identical across SDK repos; repo-specific bits in `scripts/version` + `scripts/release-check`). `release.yml` runs specs, gates on tag == version, creates the GitHub release |

## Public API surface

```crystal
require "manza"

manza = Manza::Client.new(api_key: "sk_live_...") # or MANZA_API_KEY

manza.entity.get
manza.accounts.list(currency_code: "MAD")
manza.accounts.list_transactions(account_id)
manza.customers.create(name: "Acme")
manza.payment_links.cancel(id)

# Payments (formerly transfer drafts): drafts never execute on their own.
# `transfer_drafts` is a deprecated alias of `payments` (same resource, /api/payments)
draft = manza.payments.create(account_id: a, beneficiary_id: b, amount: "150.00", client_reference: "po_1042")
authorizer.payments.authorize(id, authorization_id, signature) # `authorizer` is a client with a different API key than the creator's (`manza`)
manza.payments.decline(id, authorization_id, "wrong amount")
authorizer.transfer_authorizer.get # the enrolled authorizer: status, suspension_reason, limits

# Beneficiaries, external accounts, payee trust
manza.beneficiaries.create(beneficiary_type: "business", company_name: "Acme SARL")
manza.beneficiaries.list_external_accounts(beneficiary_id)
manza.beneficiaries.create_external_account(beneficiary_id, account_number: "0123456789")
manza.payee_trust_requests.create([external_account_id])

# Signer for machine-authorized transfers (pure functions, no HTTP)
input = Manza::TransferAuthorization.signature_input(payment_id, nonce, amount, currency_code, account_id, payee, client_reference)
Manza::TransferAuthorization.sign(signing_secret, input) # lowercase hex HMAC-SHA256

# Webhook verifier (pure functions, no HTTP); failures raise Manza::ArgumentError
event = Manza::Webhook.construct_event(raw_body, context.request.headers, signing_secret)
Manza::Webhook.verify?(raw_body, signature, timestamp, signing_secret) # Bool

begin
  manza.payments.create(...)
rescue ex : Manza::ConflictError
  ex.payment_id # the draft that already holds this client_reference
rescue ex : Manza::Error
  ex.kind # "authentication", "validation", "rate_limit", ...
end
```

- Resources on `Manza::Client`: `accounts`, `beneficiaries`, `checkout_sessions`, `customers`, `entity`, `invoices`, `payee_trust_requests`, `payment_links`, `payments`, `transfer_authorizer`, `webhook_endpoints` (plus the deprecated `transfer_drafts` alias of `payments`)
- `examples/transfer_authorizer/` is a runnable port of manza-ruby's example (creator, authorizer server, preflight), specced in `spec/examples/` against `RouteStub` (`spec/support/route_stub.cr`), not cassettes: it drives several endpoints with non-recorded responses. It requires `../../src/manza`; nothing under `src/` requires it
- `Manza::Page` is cursor-based pagination (`data`, `has_more`, `next_cursor`, `#next`), hard cap of 100 per page (`MAX_PER_PAGE`)
- Error model: one `Manza::Error` carrying a `kind` (`authentication`, `forbidden`, `not_found`, `validation`, `conflict`, `rate_limit`, `server`, `api`) plus `status`, `type`, `param`, `request_id`, `retry_after`, `body`. Match on `kind`, never on status codes or message text. `Manza::ConflictError < Manza::Error` (409) adds `payment_id`. `Manza::ArgumentError`, `Manza::ConfigurationError` and `Manza::ConnectionError` cover local misuse and transport failures
- Response bodies are `Manza::Response#body` (`JSON::Any`, snake_case, as-is). **No typed models, no auto-camelCasing.**

## How to work in this codebase

1. **Specs come first.** Every change to `src/` ships with a spec. Cassette-replay specs are the contract: they enforce the same wire format across Ruby, TS, Crystal and future SDKs.
2. **Use the SDK's primitives.** `Manza::Page`, `Manza::Error` (match on `kind`), `Resources::Base` helpers (`http_get`/`http_post`/`http_patch`/`http_delete`, `list_page`, `validate_limit!`), `encode_path` for URL construction, `fixture_id()` and `with_replay` in specs. Don't hand-roll `HTTP::Client` calls or interpolate IDs into paths.
3. **Snake-case stays.** Request and response bodies are wire format. Don't transform them.
4. **Format must be clean.** `crystal tool format --check` is gated in CI. Run `crystal tool format` to fix, never work around it.

## Critical rules

- **Never call a live Manza API** from specs, scripts or Claude sessions. Specs replay manza-ruby's cassettes only. Live staging calls create real transfers and approval requests for the team. Only manza-ruby records cassettes.
- **Cassette contract.**
  - Cassettes come from the manza-ruby release pinned in `scripts/fetch-cassettes.sh` (`PINNED_TAG`, currently `v1.3.0`; `cassettes-vX.Y.Z.tar.gz`) via that script into `spec/fixtures/cassettes/` (gitignored).
  - They are recorded against `https://ma.manza.dev`. `ReplayServer` raises if a cassette's host differs.
  - Load one cassette per spec: `payments/authorize` vs `authorize_same_key`, and `create` vs `create_duplicate`, share method + URI and the lookup is first-match.
  - The four authorize cassettes (`payments/authorize`, `authorize_same_key`, `authorize_bad_signature`, `authorize_new_payee`) use `with_replay(..., ignore_signature: true)`: the body is compared minus `signature`.
  - Every other body is compared semantically: method, path + query (host ignored, query order ignored), and JSON parsed on both sides so key order never matters (byte-for-byte when not JSON).
  - The replay server does not replay recorded response headers, so cassette responses carry no `Content-Length`.
  - The `FIXTURE_IDS` table in `spec/support/fixture_ids.cr` must stay identical to manza-ruby's `spec/support/fixture_ids.rb`.
- **Hosts.** Default `https://ma.manza.finance`, South Africa `https://za.manza.finance`, staging and cassettes `https://ma.manza.dev`. Env vars are `MANZA_API_KEY`, `MANZA_BASE_URL`, `MANZA_API_VERSION`; the pre-1.0 `ZAZU_*` names are read as a fallback for all of 1.x and warn once (`Manza::Env`). Version header is `Manza-Version`, User-Agent `manza-crystal/<version>`.
- **A replay mismatch is fixed in the SDK, never in the cassette.** "no cassette interaction matches" means the request drifted from the recording (or two cassettes sharing method + URI were loaded in one spec). Never edit a cassette or the matcher to pass, and never record here. A spec that needs a newer cassette waits on a manza-ruby release plus a deliberate `PINNED_TAG` bump. A fetch 404 means that tag has no tarball yet: re-run later or try `scripts/fetch-cassettes.sh v1.0.1`.
- **A public API break is deliberate**: named in the changelog and released as a major.
- **Never skip or weaken `crystal tool format --check`**, and never hand-edit `bin/release` or push a tag by hand (the `release.yml` gate fails when tag, `shard.yml` and `Manza::VERSION` differ).
- **Error model is shared across the SDK family.** Adding an error class or `kind` means coordinating manza-ruby and manza-ts at minimum. `ConflictError` is the 10th error class (409).
- **Signer.** `Manza::TransferAuthorization` must keep reproducing the two fixed vectors from manza-ruby's `spec/manza/transfer_authorization_spec.rb` (see `spec/manza/transfer_authorization_spec.cr`). Build the signature input from your own record of the draft, never sign the server's `signature_input` blindly.
- **Release.** `bin/release` is byte-identical across the SDK repos and is never edited in place. Repo-specific logic lives in `scripts/version` (shard.yml + `Manza::VERSION` in `src/manza.cr`) and `scripts/release-check` (shards install, fetch cassettes, format check, spec). `release.yml` gates on tag == `shard.yml` version == `Manza::VERSION`. There is no registry and no publish token: shards install from git tags, "publishing" is the tag plus the GitHub release (`GITHUB_TOKEN`, `contents: write`). Consumers depend on `github: getmanza/manza-crystal`.
- **Repo renamed `zazu-crystal` -> `manza-crystal` (org `getmanza`).** Remotes and URLs must say `getmanza/manza-crystal`.
- **CI installs Crystal after `sudo apt-get update -q`.** `crystal-lang/install-crystal` can 404 on a stale apt index; keep that step in `ci.yml` and `release.yml`.
- **Never escape backticks in PR bodies.** With `<<'EOF'` (single-quoted heredoc) the shell passes everything through verbatim. Typing `` \` `` produces literal `` \` `` in the rendered PR. See "PR descriptions" below.

## PR descriptions

Write PR description bodies in plain Markdown. **Do not escape backticks** with `` \` `` — escaping produces literal backticks instead of a monospace code span, so write `Manza::Page` directly.

The usual cause is writing the description inside a bash heredoc (`gh pr create --body "$(cat <<'EOF' ... EOF)"`) and then reflexively escaping every backtick because of shell-quoting muscle memory. With `<<'EOF'` (single-quoted delimiter) the shell does NOT interpret anything inside the heredoc — backticks, dollars, and backslashes all pass through verbatim. So write them exactly as you want them rendered:

```bash
# Good — renders as `Manza::Page` in monospace
gh pr create --body "$(cat <<'EOF'
Uses the `Manza::Page` helper.
EOF
)"

# Bad — renders as \`Manza::Page\` literally in the PR body
gh pr create --body "$(cat <<'EOF'
Uses the \`Manza::Page\` helper.
EOF
)"
```

Same rule for code blocks — write triple-backticks unescaped. The single-quoted heredoc delimiter is doing all the shell-escaping work. If you find yourself typing `` \` `` inside a PR body, stop and remove the backslash.

## Striving for excellence

These are the Karpathy guidelines we apply on every change. They reduce common LLM coding mistakes.

### 1. Think before coding

Don't assume. Don't hide confusion. Surface tradeoffs.

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity first

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Senior engineer test: would they call this overcomplicated?

### 3. Surgical changes

Touch only what you must. Clean up only your own mess.

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.
- Remove imports/variables/methods that *your* changes orphaned. Don't remove pre-existing dead code unless asked.

### 4. Goal-driven execution

Define success criteria. Loop until verified.

- "Add validation" → "Write specs for invalid inputs, then make them pass"
- "Fix the bug" → "Write a spec that reproduces it, then make it pass"
- "Refactor X" → "Ensure specs pass before and after"

For multi-step tasks, state a brief plan with verification at each step.

## Development workflow

Exact commands from `.github/workflows/ci.yml`:

```bash
# One-time setup
shards install                    # no dependencies today; release-check runs it too
scripts/fetch-cassettes.sh        # the pinned tag; or scripts/fetch-cassettes.sh v1.0.1, or `latest`

# Daily loop
crystal spec spec/manza/resources_spec.cr   # while iterating
crystal tool format --check                # CI gate (crystal tool format to fix)
crystal spec                               # full suite
scripts/release-check                      # shards install + fetch + format check + spec, as bin/release runs it

# Release (after PR merge, from a clean, up-to-date main)
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.4.0; --force re-creates
# -> bumps shard.yml + src/manza.cr, runs scripts/release-check, pushes main, publishes the GH release
# -> release.yml re-runs the specs, verifies tag == version, creates the GitHub release
```

## Agent commands

No local commands: the workflow is the `flow` plugin (`.claude/settings.json`). `/flow:lfg <issue>` takes an issue to a merge-ready PR, `/flow:plan`, `/flow:tdd`, `/flow:review-pr`, `/flow:github-review-pr|failures|comments <PR>`, `/flow:finish-prs`, `/flow:follow-through`, `/flow:debug-flaky`, and the `flow:fable-validator` agent. Sessions run on `opus` with `fable` as the advisor; each skill pins its own model.

## Workflow

Facts the `flow` skills act on. Missing line = none.

- **Verify:** `crystal tool format --check` · `crystal spec` · `scripts/release-check` (shards install + fetch cassettes + both, as `bin/release` runs it)
- **Specs:** fast loop `crystal spec spec/manza/<file>_spec.cr`; full suite `crystal spec` (replay, no network; needs `scripts/fetch-cassettes.sh` once); two worktrees at once: yes (`spec/fixtures/cassettes/` is per checkout)
- **CI:** required none; job `test` (`ci.yml`: fetch cassettes, format check, spec) and check `cubic · AI code reviewer`; full suite on the PR; failure report none
- **Review bot:** cubic; push back, citing this file, on mocks instead of cassettes, camelCased wire keys or typed models, live or recorded-here cassettes, speculative abstractions
- **Merge:** squash: `gh pr merge <PR> --squash --delete-branch`; fallback after the gate: `--admin` for the required approving review
- **PR contract:** `## Summary` (`Closes #N`), `## Fable validation` (verdict, Not verified), `## Test plan`; backticks unescaped (see PR descriptions); labels none; screenshots none
- **Conflicts:** `CHANGELOG.md`: both sides under `## [Unreleased]`, main's first; `shard.yml` and `src/manza.cr` version: main's; `bin/release`, `release.yml`: main's (release kit)
- **Worktree setup:** `scripts/fetch-cassettes.sh` (cassettes are gitignored); undo none
- **Release:** `bin/release [patch|minor|major|X.Y.Z]` from a clean, current main, which tags and pushes, then `release.yml` re-runs the specs and creates the GitHub release; changelog `CHANGELOG.md`, `[Unreleased]` headed `## [X.Y.Z]` by hand; lockfiles none
- **Main health:** `gh run list --workflow ci.yml --branch main --event push --limit 1 --json conclusion,headSha`
- **Upstream:** libraries we own `getmanza/*` (release kit); scrub none

## Cross-SDK contract

`manza-ruby` is the reference implementation:

- Records cassettes against `https://ma.manza.dev`
- Ships them as a release tarball (`cassettes-vX.Y.Z.tar.gz`) on each version
- All other SDKs (`manza-ts`, `manza-crystal`, future `manza-python`, `manza-go`, `manza-php`, `manza-elixir`, `manza-rust`) replay these cassettes in their own test harness

If the contract breaks (e.g., new request shape), it's a coordinated change across at least two repos: manza-ruby and manza-ts.

## Repository links

- Ruby SDK (reference): https://github.com/getmanza/manza-ruby
- TypeScript SDK: https://github.com/getmanza/manza-ts
- This repo: https://github.com/getmanza/manza-crystal
- Registry: none. Install via `github: getmanza/manza-crystal` in `shard.yml`; releases at https://github.com/getmanza/manza-crystal/releases
