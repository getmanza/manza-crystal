# zazu-crystal

Crystal SDK for the [Manza](https://ma.manza.finance) (Zazu) API.

```yaml
# shard.yml
dependencies:
  zazu:
    github: getzazu/zazu-crystal
```

```crystal
require "zazu"

client = Zazu::Client.new # reads ZAZU_API_KEY

entity = client.entity.get

page = client.accounts.list
page.data.each do |account|
  puts "#{account["id"]} #{account["name"]}"
end

# Initiate a transfer — it lands in your workspace's in-app approval
# queue; the API never executes a transfer itself.
draft = client.transfer_drafts.create(
  account_id: account_id,
  beneficiary_id: beneficiary_id,
  amount: "150.00",
  payment_reference: "INV-000042",
  client_reference: "po_1042" # unique per entity; a duplicate raises Zazu::ConflictError
)

# Save a recipient and its bank account, then ask for the payee to be trusted.
beneficiary = client.beneficiaries.create(beneficiary_type: "business", company_name: "Acme SARL")
account = client.beneficiaries.create_external_account(
  beneficiary.body["id"].as_s, account_number: "0123456789"
)
client.payee_trust_requests.create([account.body["id"].as_s])
```

## Machine-authorized transfers

A draft inside your entity's authorization envelope (trusted payee,
within limits) is sent to your enrolled authorizer endpoint as a
`payment.authorization_requested` webhook carrying an `authorization.id`
and a one-time `nonce`. Sign the draft from **your own record** of it
with the endpoint's signing secret, and authorize it with a **different
API key** from the one that created it (the creating key gets 403
`same_key_forbidden`):

```crystal
input = Zazu::TransferAuthorization.signature_input(
  draft["id"].as_s, nonce, draft["amount"].as_s, draft["currency_code"].as_s,
  draft["account_id"].as_s,
  Zazu::TransferAuthorization.payee_for(external_account_id: draft["external_account_id"].as_s),
  draft["client_reference"].as_s? # optional
)
signature = Zazu::TransferAuthorization.sign(signing_secret, input) # lowercase hex HMAC-SHA256

authorizer = Zazu::Client.new(api_key: ENV["ZAZU_AUTHORIZER_API_KEY"])
authorizer.transfer_drafts.authorize(draft["id"].as_s, authorization_id, signature)
authorizer.transfer_drafts.decline(draft["id"].as_s, authorization_id, "Not ours") # reason is optional
```

`amount` must be the API's decimal string verbatim (e.g. `"2500.0"`).
`payee_for` takes exactly one of `external_account_id` or
`destination_account_id`. A blank signature raises `Zazu::ArgumentError`
locally, because the API counts it as a failed attempt. A wrong
signature raises `Zazu::Error` (`kind` `validation`, `type`
`invalid_signature`); five on one challenge send the draft to your
in-app approvers, and five in a row suspend the authorizer.

## Response shape

Response bodies are returned as-is from the API — `snake_case` keys as
`JSON::Any`, no typed models. The same shape ships across every Zazu
SDK (Ruby, TypeScript, Python, Go, ...) so the cassette contract is
one-to-one. Optional response keys (`tax_id`, `ice_number`, and
`delivery_date` on invoices are Morocco-only) are simply absent from the
`JSON::Any` outside that market; new fields such as `client_reference`,
`authorization`, `settled_at`, `transaction` and `billing_address`, and
the `clearing` status on checkout sessions and payment links, need no
SDK change.

## Pagination

List endpoints return a `Zazu::Page` (`data`, `has_more`, `next_cursor`)
with a `#next` method that fetches the following page, or `nil` on the
last one. Page size is capped at 100.

## Errors

Non-2xx responses raise `Zazu::Error` with `status`, `kind`
(`authentication`, `forbidden`, `not_found`, `validation`, `conflict`,
`rate_limit`, `server`, `api`), the API's `type`/`message`/`param`, the
`request_id`, and `retry_after` for 429s. 400 and 422 are both
`validation`. 409 raises `Zazu::ConflictError` (`kind` `conflict`), which
adds `payment_id` — for a duplicate `client_reference`, the draft that
already holds it. Transport failures raise
`Zazu::ConnectionError`; a client misconfiguration (missing API key)
raises `Zazu::ConfigurationError`.

## Configuration

| Option | Env var | Default |
|--------|---------|---------|
| `api_key` | `ZAZU_API_KEY` | required |
| `base_url` | `ZAZU_BASE_URL` | `https://ma.manza.finance` |
| `api_version` (Zazu-Version header) | `ZAZU_API_VERSION` | unset |
| `timeout` | — | 30 seconds |

Production is `https://ma.manza.finance` (Morocco); for South Africa
pass `base_url: "https://za.manza.finance"`. The cassettes are recorded
against staging at `https://ma.manza.dev`.

## Tests

Tests replay the canonical cassettes recorded by
[zazu-ruby](https://github.com/getzazu/zazu-ruby). The cassettes are
downloaded from the Ruby SDK's release tarball and served from a
stdlib `HTTP::Server`. Same interactions, same assertions, every
language.

```bash
scripts/fetch-cassettes.sh
crystal spec
```

## The SDK family

- [zazu-ruby](https://github.com/getzazu/zazu-ruby) — reference implementation (records the cassettes)
- [zazu-ts](https://github.com/getzazu/zazu-ts)
- [zazu-python](https://github.com/getzazu/zazu-python)
- [zazu-go](https://github.com/getzazu/zazu-go)
- [cli](https://github.com/getzazu/cli)

## Releasing

```bash
bin/release list        # last releases + what patch/minor/major would give
bin/release --dry-run   # version + changes since the last tag, publishes nothing
bin/release minor       # or patch (default), major, an explicit 0.3.0; --force re-creates
# → bumps shard.yml + src/zazu.cr, runs scripts/release-check, pushes main, publishes the GH release
# → release.yml re-runs the specs and verifies the tag matches shard.yml and Zazu::VERSION
```

`bin/release` is the zazu SDK release kit (byte-identical across SDK repos;
repo-specific bits live in `scripts/version` and `scripts/release-check`).
