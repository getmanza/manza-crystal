# zazu-crystal

Crystal SDK for the Zazu (Manza) API. It **replays zazu-ruby's cassettes** in its own spec harness. zazu-ruby is the reference implementation: it records cassettes, ships them as a release tarball, and every other SDK (zazu-ts, zazu-crystal, ...) proves wire-format parity by replaying them.

## Stack

| Concern | Tool | Notes |
|---|---|---|
| Language | Crystal, `crystal: ">= 1.10.0"` | `shard.yml`. CI runs `crystal: latest` (single version, no matrix) |
| HTTP | stdlib `HTTP::Client` | `src/zazu/client.cr`. No shard dependencies |
| Test runner | `crystal spec` | `spec/` |
| Cassette replay (tests) | Stdlib `HTTP::Server` + YAML | `spec/support/replay_server.cr` reads zazu-ruby's VCR YAML. `spec/support/stub_server.cr` is for non-cassette cases |
| Format | `crystal tool format` | CI runs `--check`. No separate linter or typecheck step: the compiler is the typecheck |
| Package registry | None | Shards install straight from git tags (`github: getmanza/zazu-crystal`) |
| Release | `bin/release` | zazu SDK release kit (byte-identical across SDK repos; repo-specific bits in `scripts/version` + `scripts/release-check`). `release.yml` runs specs, gates on tag == version, creates the GitHub release |

## Public API surface

```crystal
require "zazu"

zazu = Zazu::Client.new(api_key: "sk_live_...") # or ZAZU_API_KEY

zazu.entity.get
zazu.accounts.list(currency_code: "MAD")
zazu.accounts.list_transactions(account_id)
zazu.customers.create(name: "Acme")
zazu.payment_links.cancel(id)

# Transfers (0.3.0): drafts never execute on their own
draft = zazu.transfer_drafts.create(account_id: a, beneficiary_id: b, amount: "150.00", client_reference: "po_1042")
zazu.transfer_drafts.authorize(id, authorization_id, signature) # a different API key than the creator's
zazu.transfer_drafts.decline(id, authorization_id, "wrong amount")

# Beneficiaries, external accounts, payee trust
zazu.beneficiaries.create(beneficiary_type: "business", company_name: "Acme SARL")
zazu.beneficiaries.list_external_accounts(beneficiary_id)
zazu.beneficiaries.create_external_account(beneficiary_id, account_number: "0123456789")
zazu.payee_trust_requests.create([external_account_id])

# Signer for machine-authorized transfers (pure functions, no HTTP)
input = Zazu::TransferAuthorization.signature_input(payment_id, nonce, amount, currency_code, account_id, payee, client_reference)
Zazu::TransferAuthorization.sign(signing_secret, input) # lowercase hex HMAC-SHA256

begin
  zazu.transfer_drafts.create(...)
rescue ex : Zazu::ConflictError
  ex.payment_id # the draft that already holds this client_reference
rescue ex : Zazu::Error
  ex.kind # "authentication", "validation", "rate_limit", ...
end
```

- Resources on `Zazu::Client`: `accounts`, `beneficiaries`, `checkout_sessions`, `customers`, `entity`, `invoices`, `payee_trust_requests`, `payment_links`, `transfer_drafts`, `webhook_endpoints`
- `Zazu::Page` is cursor-based pagination (`data`, `has_more`, `next_cursor`, `#next`), hard cap of 100 per page (`MAX_PER_PAGE`)
- Error model: one `Zazu::Error` carrying a `kind` (`authentication`, `forbidden`, `not_found`, `validation`, `conflict`, `rate_limit`, `server`, `api`) plus `status`, `type`, `param`, `request_id`, `retry_after`, `body`. Match on `kind`, never on status codes or message text. `Zazu::ConflictError < Zazu::Error` (409) adds `payment_id`. `Zazu::ArgumentError`, `Zazu::ConfigurationError` and `Zazu::ConnectionError` cover local misuse and transport failures
- Response bodies are `Zazu::Response#body` (`JSON::Any`, snake_case, as-is). **No typed models, no auto-camelCasing.**

## How to work in this codebase

1. **Specs come first.** Every change to `src/` ships with a spec. Cassette-replay specs are the contract: they enforce the same wire format across Ruby, TS, Crystal and future SDKs.
2. **Use the SDK's primitives.** `Zazu::Page`, `Zazu::Error` (match on `kind`), `Resources::Base` helpers (`http_get`/`http_post`/`http_patch`/`http_delete`, `list_page`, `validate_limit!`), `encode_path` for URL construction, `fixture_id()` and `with_replay` in specs. Don't hand-roll `HTTP::Client` calls or interpolate IDs into paths.
3. **Snake-case stays.** Request and response bodies are wire format. Don't transform them.
4. **Format must be clean.** `crystal tool format --check` is gated in CI. Run `crystal tool format` to fix, never work around it.

## Critical rules

- **Never call a live Zazu/Manza API** from specs, scripts or Claude sessions. Specs replay zazu-ruby's cassettes only. Live staging calls create real transfers and approval requests for the team. Only zazu-ruby records cassettes.
- **Cassette contract.**
  - Cassettes come from the newest zazu-ruby `v*` release (`cassettes-vX.Y.Z.tar.gz`) via `scripts/fetch-cassettes.sh` into `spec/fixtures/cassettes/` (gitignored).
  - They are recorded against `https://ma.manza.dev`. `ReplayServer` raises if a cassette's host differs.
  - Load one cassette per spec: `transfer_drafts/authorize` vs `authorize_same_key`, and `create` vs `create_duplicate`, share method + URI and the lookup is first-match.
  - The three authorize cassettes use `with_replay(..., ignore_signature: true)`: the body is compared minus `signature`.
  - Every other body is compared semantically: method, path + query (host ignored, query order ignored), and JSON parsed on both sides so key order never matters (byte-for-byte when not JSON).
  - The replay server does not replay recorded response headers, so cassette responses carry no `Content-Length`.
  - The `FIXTURE_IDS` table in `spec/support/fixture_ids.cr` must stay identical to zazu-ruby's `spec/support/fixture_ids.rb`.
- **Hosts.** Default `https://ma.manza.finance`, South Africa `https://za.manza.finance`, staging and cassettes `https://ma.manza.dev`. Env var names stay `ZAZU_*` (`ZAZU_API_KEY`, `ZAZU_BASE_URL`, `ZAZU_API_VERSION`) and the namespace stays `Zazu` until the rename plan (zazu-ruby `docs/plans/2026-10-manza-rename.md`).
- **Error model is shared across the SDK family.** Adding an error class or `kind` means coordinating zazu-ruby and zazu-ts at minimum. The 10th is the conflict (409).
- **Signer.** `Zazu::TransferAuthorization` must keep reproducing the two fixed vectors from zazu-ruby's `spec/zazu/transfer_authorization_spec.rb` (see `spec/zazu/transfer_authorization_spec.cr`). Build the signature input from your own record of the draft, never sign the server's `signature_input` blindly.
- **Release.** `bin/release` is byte-identical across the SDK repos and is never edited in place. Repo-specific logic lives in `scripts/version` (shard.yml + `Zazu::VERSION` in `src/zazu.cr`) and `scripts/release-check` (shards install, fetch cassettes, format check, spec). `release.yml` gates on tag == `shard.yml` version == `Zazu::VERSION`. There is no registry and no publish token: shards install from git tags, "publishing" is the tag plus the GitHub release (`GITHUB_TOKEN`, `contents: write`). Consumers depend on `github: getmanza/zazu-crystal`.
- **Repo moved from `getzazu` to `getmanza`.** Remotes and URLs must say `getmanza`.
- **CI installs Crystal after `sudo apt-get update -q`.** `crystal-lang/install-crystal` can 404 on a stale apt index; keep that step in `ci.yml` and `release.yml`.
- **Never escape backticks in PR bodies.** With `<<'EOF'` (single-quoted heredoc) the shell passes everything through verbatim. Typing `` \` `` produces literal `` \` `` in the rendered PR. See "PR descriptions" below.

## PR descriptions

Write PR description bodies in plain Markdown. **Do not escape backticks** with `` \` `` — GitHub renders `` \` `` literally as a backslash followed by a backtick, producing output like `` \`Zazu::Page\` `` instead of the monospace `Zazu::Page` the reader expects.

The usual cause is writing the description inside a bash heredoc (`gh pr create --body "$(cat <<'EOF' ... EOF)"`) and then reflexively escaping every backtick because of shell-quoting muscle memory. With `<<'EOF'` (single-quoted delimiter) the shell does NOT interpret anything inside the heredoc — backticks, dollars, and backslashes all pass through verbatim. So write them exactly as you want them rendered:

```bash
# Good — renders as `Zazu::Page` in monospace
gh pr create --body "$(cat <<'EOF'
Uses the `Zazu::Page` helper.
EOF
)"

# Bad — renders as \`Zazu::Page\` literally in the PR body
gh pr create --body "$(cat <<'EOF'
Uses the \`Zazu::Page\` helper.
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
scripts/fetch-cassettes.sh        # newest zazu-ruby release; or scripts/fetch-cassettes.sh v0.3.0

# Daily loop
crystal spec spec/zazu/resources_spec.cr   # while iterating
crystal tool format --check                # CI gate (crystal tool format to fix)
crystal spec                               # full suite
scripts/release-check                      # shards install + fetch + format check + spec, as bin/release runs it

# Release (after PR merge, from a clean, up-to-date main)
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.4.0; --force re-creates
# -> bumps shard.yml + src/zazu.cr, runs scripts/release-check, pushes main, publishes the GH release
# -> release.yml re-runs the specs, verifies tag == version, creates the GitHub release
```

## Models

Sessions run on `opus` (Opus 5.5) with `fable` (Fable 5.1) as the advisor (`.claude/settings.json`). Fable is spent where judgment matters most: plans are written on Fable, the advisor is consulted at decision points (before choosing an approach, a schema or public API, a migration, a dependency, anything irreversible, and when a failure repeats), and the `fable-validator` agent checks every finished implementation before its pull request opens (`/lfg`, Phase 6.5). Commands pin their tier by alias, never by full model ID: `opus` for orchestration, security, full PR review, payments and production debugging; `sonnet` for the implementation specialists and TDD; `haiku` for mechanical scans. Every spawned agent names its `model:`; one that does not runs on `sonnet` (`CLAUDE_CODE_SUBAGENT_MODEL`), never on the session's model. Plan mode cannot take a model of its own: it runs on Opus and asks the advisor.

## Slash commands

These live in `.claude/commands/` and are available in any Claude Code session:

| Command | When |
|---|---|
| `/lfg <issue or feature>` | Full autonomous workflow with TDD + verification |
| `/github-review-pr <PR#>` | Full PR review pass — failures first, then comments |
| `/github-review-failures <PR#>` | Just fix CI failures on a PR |
| `/github-review-comments <PR#>` | Just respond to reviewer comments on a PR |
| `/coderabbit-review <PR#>` | Specifically address CodeRabbit findings (verify, fix valid, push back on stale/wrong) |

## Cross-SDK contract

`zazu-ruby` is the reference implementation:

- Records cassettes against `https://ma.manza.dev`
- Ships them as a release tarball (`cassettes-vX.Y.Z.tar.gz`) on each version
- All other SDKs (`zazu-ts`, `zazu-crystal`, future `zazu-python`, `zazu-go`, `zazu-php`, `zazu-elixir`, `zazu-rust`) replay these cassettes in their own test harness

If the contract breaks (e.g., new request shape), it's a coordinated change across at least two repos: zazu-ruby and zazu-ts.

## Repository links

- Ruby SDK (reference): https://github.com/getmanza/zazu-ruby
- TypeScript SDK: https://github.com/getmanza/zazu-ts
- This repo: https://github.com/getmanza/zazu-crystal
- Registry: none. Install via `github: getmanza/zazu-crystal` in `shard.yml`; releases at https://github.com/getmanza/zazu-crystal/releases
