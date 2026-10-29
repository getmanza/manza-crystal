# manza-crystal

Crystal SDK for the [Manza](https://ma.manza.finance) API.

```yaml
# shard.yml
dependencies:
  manza:
    github: getmanza/manza-crystal
```

```crystal
require "manza"

client = Manza::Client.new # reads MANZA_API_KEY

entity = client.entity.get

page = client.accounts.list
page.data.each do |account|
  puts "#{account["id"]} #{account["name"]}"
end

# Initiate a transfer — it lands in your workspace's in-app approval
# queue; the API never executes a transfer itself.
draft = client.payments.create(
  account_id: account_id,
  beneficiary_id: beneficiary_id,
  amount: "150.00",
  payment_reference: "INV-000042",
  client_reference: "po_1042" # unique per entity; a duplicate raises Manza::ConflictError
)
# client.transfer_drafts is a deprecated alias of client.payments (same methods, /api/payments)

# Save a recipient and its bank account, then ask for the payee to be trusted.
beneficiary = client.beneficiaries.create(beneficiary_type: "business", company_name: "Acme SARL")
account = client.beneficiaries.create_external_account(
  beneficiary.body["id"].as_s, account_number: "0123456789"
)
client.payee_trust_requests.create([account.body["id"].as_s])
```

## Machine-authorized transfers

A draft inside your entity's authorization envelope (trusted payee, or a
new one when you allow it, within limits) is sent to your enrolled
authorizer endpoint as a `payment.authorization_requested` webhook
carrying an `authorization.id` and a one-time `nonce`. Your system checks
it against its own ledger, signs it and authorizes it with a **different
API key** from the one that created it.
[`examples/transfer_authorizer/`](examples/transfer_authorizer/) runs the
whole flow. The guide is the
[transfer authorization docs](https://ma.manza.finance/docs/api/transfer-authorization).

### Setup, step by step

1. **Feature flags.** Ask support to enable API transfers and transfer authorization (`release_api_webhook_authorization`) on your workspace.
2. **Two API keys.** Key A creates drafts (`transfers:write`; `beneficiaries:request_trust` for step 6; `entity:read`, `accounts:read`, `webhook_endpoints:read` and `beneficiaries:read` for the preflight in step 7). Key B answers the challenges (`transfers:authorize`). The creating key is always refused with 403 `same_key_forbidden`, so keep key B and the signing secret on the system that holds your ledger. Bind key B to an IP allowlist: authorizing from a key without one is refused with 403 `unrestricted_api_key`. Bind key A to one too if you allow new payees (step 6): a draft to a new payee from a key without an allowlist goes to your approvers (`unrestricted_api_key`).
3. **A stable public URL.** Your authorizer needs an HTTPS URL that never changes: an enrolled endpoint's URL is locked. Use a reserved ngrok domain (`ngrok http --url=your-name.ngrok.app 4599`) or a named Cloudflare tunnel. Never a free ngrok URL: it changes on every restart.
4. **Create the webhook endpoint** at that URL:

   ```crystal
   client.webhook_endpoints.create(url: "https://your-name.ngrok.app/", events: ["transfer.executed"])
   ```

5. **Enrol it in the app**: Settings → Developer → Transfer approval. Pick the endpoint, the currency and both limits, confirm with your two-factor code, and copy the signing secret: it is shown once.
6. **Allow new payees, or trust each payee.** Turn on *Approve transfers to new payees* at enrolment (or later, same page, with your two-factor code) and set the *Limit per transfer to a new payee*. Your authorizer may then approve a transfer to bank details your workspace never trusted, up to that limit, and its signature trusts them: the webhook's `payment.payee_trusted` is `false` for such a transfer. Bank details whose trust was revoked, or that were edited after trusting, still go to your approvers. Without the option, an approver marks the beneficiary's bank account as trusted from the Beneficiaries list, or you ask them to:

   ```crystal
   client.payee_trust_requests.create(["01a1..."])
   ```

   `trusted` on `client.beneficiaries.get_external_account` says which it is. The API does not show whether the option is on.
7. **Run the preflight, then the example** (from `examples/transfer_authorizer/`, after filling in `.env`): `crystal run preflight.cr` checks what the API shows of steps 1–6 and prints a fix for each that fails. What it cannot see, check by hand: that key B is bound to an IP allowlist, and, for a payee not trusted yet, that *Approve transfers to new payees* is on and key A is bound to an IP allowlist too (it warns, it does not fail). Then `crystal run server.cr` in one terminal, `crystal run create_transfer.cr` in another.
8. **Troubleshooting**: a draft that goes to your approvers instead has an `authorization` with status `refused` and a `refusal_reason` (`create_transfer.cr` prints it in words); `client.transfer_authorizer.get` shows a suspension and its `suspension_reason`. An authorize answered 409 `authorization_busy` (a bank-detail edit, trust or trust revocation on the same payee was in flight) is safe to retry. The reasons, and an API error's `type`, are in the [transfer authorization docs](https://ma.manza.finance/docs/api/transfer-authorization).

### Verifying the webhook

Pass the **raw request body**, never re-serialized JSON. `construct_event`
reads `X-Manza-Signature` and `X-Manza-Timestamp` (any case, or the legacy
`X-Zazu-*` names), checks the signature in constant time and the
timestamp within 5 minutes, and returns the parsed event (a `JSON::Any`
object). It raises `Manza::ArgumentError` otherwise:

```crystal
server = HTTP::Server.new do |context|
  body = context.request.body.try(&.gets_to_end) || ""
  event = begin
    Manza::Webhook.construct_event(body, context.request.headers, signing_secret)
  rescue ex : Manza::ArgumentError
    context.response.status_code = 401
    next
  end
  # event["event"] # => "payment.authorization_requested"
end
```

`Manza::Webhook.verify?(payload, signature, timestamp, secret)` returns a
`Bool` instead. Both accept `tolerance: nil` to skip the timestamp check.
Use it only to replay a captured delivery in a local tool or test, never
on a live endpoint: without the check, anyone holding a captured delivery
can replay it.

### Signing the challenge

Sign the draft from **your own record** of it with the endpoint's
signing secret:

```crystal
# draft: your own record of the draft, e.g. the JSON::Any body of the
# create response (client.payments.create(...).body), stored in your ledger
authorization = event["data"]["authorization"]
input = Manza::TransferAuthorization.signature_input(
  draft["id"].as_s, authorization["nonce"].as_s,
  draft["amount"].as_s, # the API's decimal string verbatim, e.g. "2500.0"
  draft["currency_code"].as_s, draft["account_id"].as_s,
  Manza::TransferAuthorization.payee_for(external_account_id: draft["external_account_id"].as_s),
  draft["client_reference"].as_s? # optional
)
signature = Manza::TransferAuthorization.sign(signing_secret, input) # lowercase hex HMAC-SHA256

authorizer = Manza::Client.new(api_key: ENV["MANZA_AUTHORIZER_API_KEY"])
authorizer.payments.authorize(draft["id"].as_s, authorization["id"].as_s, signature)
authorizer.payments.decline(draft["id"].as_s, authorization["id"].as_s, "Not ours") # reason is optional
```

`payee_for` takes exactly one of `external_account_id` or
`destination_account_id`. A blank signature raises `Manza::ArgumentError`
locally, because the API counts it as a failed attempt. A wrong
signature raises `Manza::Error` (`kind` `validation`, `type`
`invalid_signature`); five on one challenge send the draft to your
in-app approvers, and five in a row suspend the authorizer.

## Response shape

Response bodies are returned as-is from the API — `snake_case` keys as
`JSON::Any`, no typed models. The same shape ships across every Manza
SDK (Ruby, TypeScript, Python, Go, ...) so the cassette contract is
one-to-one. Optional response keys (`tax_id`, `ice_number`, and
`delivery_date` on invoices are Morocco-only) are simply absent from the
`JSON::Any` outside that market; new fields such as `client_reference`,
`authorization` (with `refusal_reason`), `settled_at`, `transaction`,
`billing_address`, `trusted` on external accounts, and
the `clearing` status on checkout sessions and payment links, need no
SDK change.

## Pagination

List endpoints return a `Manza::Page` (`data`, `has_more`, `next_cursor`)
with a `#next` method that fetches the following page, or `nil` on the
last one. Page size is capped at 100.

## Errors

Non-2xx responses raise `Manza::Error` with `status`, `kind`
(`authentication`, `forbidden`, `not_found`, `validation`, `conflict`,
`rate_limit`, `server`, `api`), the API's `type`/`message`/`param`, the
`request_id`, and `retry_after` for 429s. 400 and 422 are both
`validation`. 409 raises `Manza::ConflictError` (`kind` `conflict`), which
adds `payment_id` — for a duplicate `client_reference`, the draft that
already holds it. Transport failures raise
`Manza::ConnectionError`; a client misconfiguration (missing API key)
raises `Manza::ConfigurationError`.

## Configuration

| Option | Env var | Default |
|--------|---------|---------|
| `api_key` | `MANZA_API_KEY` | required |
| `base_url` | `MANZA_BASE_URL` | `https://ma.manza.finance` |
| `api_version` (Manza-Version header) | `MANZA_API_VERSION` | unset |
| `timeout` | — | 30 seconds |

The pre-1.0 `ZAZU_API_KEY`, `ZAZU_BASE_URL` and `ZAZU_API_VERSION` are still
read when the `MANZA_*` name is unset, with a one-time deprecation warning on
stderr, for all of 1.x.

Production is `https://ma.manza.finance` (Morocco); for South Africa
pass `base_url: "https://za.manza.finance"`. The cassettes are recorded
against staging at `https://ma.manza.dev`.

## Tests

Tests replay the canonical cassettes recorded by
[manza-ruby](https://github.com/getmanza/manza-ruby). The cassettes are
downloaded from the Ruby SDK's release tarball and served from a
stdlib `HTTP::Server`. Same interactions, same assertions, every
language.

```bash
scripts/fetch-cassettes.sh
crystal spec
```

## The SDK family

| SDK | Repository | Install |
|---|---|---|
| Ruby (reference implementation, records the cassettes) | [getmanza/manza-ruby](https://github.com/getmanza/manza-ruby) | `gem "manza"` |
| TypeScript / JavaScript | [getmanza/manza-ts](https://github.com/getmanza/manza-ts) | `npm install @getmanza/sdk` |
| Python | [getmanza/manza-python](https://github.com/getmanza/manza-python) | `pip install manza` |
| Go | [getmanza/manza-go](https://github.com/getmanza/manza-go) | `go get github.com/getmanza/manza-go` |
| PHP | [getmanza/manza-php](https://github.com/getmanza/manza-php) | `composer require manza/manza-php` |
| Rust | [getmanza/manza-rust](https://github.com/getmanza/manza-rust) | `cargo add manza` |
| Crystal | [getmanza/manza-crystal](https://github.com/getmanza/manza-crystal) (this repo) | shard `manza` (`github: getmanza/manza-crystal`) |
| Elixir | [getmanza/manza-elixir](https://github.com/getmanza/manza-elixir) | `{:manza, "~> 1.0"}` |
| CLI | [getmanza/cli](https://github.com/getmanza/cli) | `npm install -g @getzazu/cli` or `brew install getmanza/tap/zazu` |

## Releasing

```bash
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.3.0; --force re-creates
# → bumps shard.yml + src/manza.cr, runs scripts/release-check, pushes main, publishes the GH release
# → release.yml re-runs the specs and verifies the tag matches shard.yml and Manza::VERSION
```

`bin/release` is the manza SDK release kit (byte-identical across SDK repos;
repo-specific bits live in `scripts/version` and `scripts/release-check`).
