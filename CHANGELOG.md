# Changelog

All notable changes to `manza-crystal` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-11-14

Ports manza-ruby 2.0.0, synced to the Manza API at getmanza/app
`906ec486e5` (API version `2026-11-13`). A major release: see Migrating
from 1.x below.

### Removed

- **Breaking:** `client.invoices.create_payment_link` (`POST
  /api/invoices/:id/payment_link`). The API retired the endpoint: ask for
  the link with `generate_payment_link: true` on `invoices.create` or
  `invoices.update` instead.
- **Breaking:** the v1 transfer-authorization signer.
  `Manza::TransferAuthorization` builds only the v2 input (below).

### Changed

- **Breaking:** `Manza::TransferAuthorization::SIGNATURE_VERSION` is
  `manza.transfer-authorization.v2`, and `signature_input` takes a required
  named argument `transfer_method:` (`String?`), appended after
  `client_reference` (`""` when nil):
  `manza.transfer-authorization.v2|payment_id|nonce|amount|currency_code|account_id|payee|client_reference|transfer_method`.
  A 1.x call without it no longer compiles. The API verifies v2 for every
  request that is unpinned or sends `Manza-Version: 2026-11-13`; only
  `2026-03-27` still verifies v1. Pass the payment's `transfer_method` as
  the API returned it.
- The example authorizer (`examples/transfer_authorizer`) records the
  create response's `transfer_method` in its ledger, checks it against the
  webhook's `payment.transfer_method`, signs v2, and compares its input with
  the webhook's `signature_input_v2`. `Ledger#record` takes
  `transfer_method`.
- Invoice docs: `account_id` is required on `invoices.create` (without one
  the API answers 422 `state_error`; an account that is not the entity's,
  422 with `param` `account_id`), and `invoices.update` takes it too. An
  invoice's `status` may be `declined`, and `invoices.delete` also takes a
  `declined` invoice that has no number.
- Cassettes are pinned to manza-ruby `v2.0.0` (`cassettes-v2.0.0.tar.gz`).

### Added

- `Manza::PlanLimitReachedError < Manza::Error`, raised for a 422 whose
  `type` is `plan_limit_reached` (a plan cap, which the API used to answer
  with a 500). Its `kind` stays `validation`; `#limit_kind`, `#current` and
  `#max` read the cap from the error body. The API's `error.kind` is read
  as `limit_kind` because `Manza::Error#kind` is already the error's
  category (manza-ruby and manza-python name it `kind`, manza-go
  `LimitKind`).
- `generate_payment_link` on `invoices.create` and `invoices.update` (needs
  the `payment_links:write` scope; taken only while payment links are
  enabled for the entity). Invoice responses carry `generate_payment_link`
  and the embedded `account`.
- `transfer_method` on `payments.create`: `eft` or `rtc` in South Africa,
  `standard` or `instant` in Morocco; one the market does not offer raises
  `Manza::Error` (`kind` `validation`) with `param` `transfer_method`.
  Payment responses carry `transfer_method` (the rail sent, the provider's
  default when left out, null where the market offers no choice).
- Documented: the authorization `refusal_reason` `rail_limit_exceeded`
  (status `superseded`): an authorized transfer over its rail's limit at
  execution, sent to the approvers; the authorize call raises a 422
  `Manza::Error` (`state_error`). A non-boolean `generate_payment_link`
  raises `Manza::Error` (`kind` `validation`, 400).
- Documented: the `payment.authorization_requested` webhook's
  `signature_input_v2` and `payment.transfer_method`, and
  `transfer_authorizer.get`'s `trust_new_payees` and `new_payee_limit`.

### Fixed (API side, no wire change)

- `accounts.list_transactions` and `accounts.get_transaction` return
  posted movements only (getmanza/app 818432457a); the SDK is unchanged.

### Migrating from 1.x

- **`create_payment_link` is gone.** Replace
  `client.invoices.create_payment_link(id, account_id)` with
  `client.invoices.update(id, account_id: account_id, generate_payment_link: true)`,
  or pass `generate_payment_link: true` on create. `update` returns the
  invoice, not a link: the link is made from the invoice's account when
  the invoice is approved, and appears in the invoice's `payment_link`.
  `update` takes only an invoice that is still `draft`,
  `pending_approval` or `declined` (any other raises `Manza::Error`,
  `kind` `validation`, `type` `state_error`); for an invoice already
  approved or sent, there is no API path to attach a link to it:
  `client.payment_links.create(account_id: ..., amount: ..., ...)` makes a
  standalone link instead.
- **`account_id` is required on invoice create.** Pass the account the
  invoice is paid into (`client.accounts.list`); 1.x calls without it now
  raise `Manza::Error` (`kind` `validation`, `type` `state_error`).
- **v2 signatures only.** Add `transfer_method: payment["transfer_method"].as_s?`
  to every `Manza::TransferAuthorization.signature_input` call (the
  compiler points at each one), and compare with the webhook's
  `signature_input_v2` instead of `signature_input`. A client pinned to
  `Manza-Version: 2026-03-27` (`api_version:` or `MANZA_API_VERSION`) is
  verified v1 and must stay on manza-crystal 1.x; unpin it, or pin
  `2026-11-13`, to move to 2.0.
- **Plan caps.** A `kind == "server"` check around creates that may hit a
  plan cap no longer matches it: rescue `Manza::PlanLimitReachedError` (or
  match `kind == "validation"`), and do not retry it.
- **Example ledger.** An entry written by the 1.x example has no
  `transfer_method`: it still matches a draft whose `transfer_method` is
  null, but a draft that carries one is declined as a mismatch. Let open
  challenges finish (or expire) before upgrading, or add
  `"transfer_method"` from `payments.get` to those entries.

## [1.1.0]

Ports manza-ruby 1.1.0 to 1.3.0.

### Added

- `Manza::Webhook` verifies incoming deliveries: `verify?(payload,
  signature, timestamp, secret)` returns a `Bool`, `construct_event(payload,
  headers, secret)` returns the parsed event (always a JSON object) or
  raises `Manza::ArgumentError`, and `sign` builds a signature for tests.
  The signed content is `"<timestamp>.<raw body>"` (hex HMAC-SHA256,
  constant-time compare); the timestamp must be within 300 s
  (`tolerance: nil` skips it); headers are read case-insensitively,
  `X-Manza-*` first, then `X-Zazu-*`. Passes the vector shared across SDKs.
- `client.payments`, the canonical resource for API-initiated transfers:
  `create`, `get`, `authorize` and `decline` on `/api/payments`. Bodies and
  the transfer-authorization signature input are unchanged.
- `client.transfer_authorizer.get` (`GET /api/transfer_authorizer`): the
  enrolled authorizer's status, `suspension_reason`, currency, limits,
  secret expiry and webhook endpoint. Nothing enrolled raises `Manza::Error`
  with `kind` `not_found`.
- `examples/transfer_authorizer/`: a creator (`create_transfer.cr`), an
  authorizer on stdlib `HTTP::Server` (`server.cr`) and a `preflight.cr`
  that checks every setup step, ported from manza-ruby with the same env
  vars, checks and log lines, and specs under `spec/examples/`. Shards
  install a dependency's whole git tree, so the files are on disk in an
  installed shard; nothing under `src/` requires them.
- README: "Setup, step by step" for machine-authorized transfers, a
  verifier snippet, and links to the example and the
  [transfer authorization docs](https://ma.manza.finance/docs/api/transfer-authorization).
- New response fields need no SDK change and pass through as-is:
  `authorization.refusal_reason`, `trusted` on external accounts, and
  `payment.payee_trusted` in the `payment.authorization_requested` webhook.

### Deprecated

- `client.transfer_drafts` is an alias of `client.payments` (same resource,
  same methods, now calling `/api/payments`) and warns at compile time; it
  stays for all of 1.x. `Manza::Resources::TransferDrafts` is an alias of
  `Manza::Resources::Payments`.

### Changed

- Cassettes are pinned to manza-ruby `v1.3.0` (`cassettes-v1.3.0.tar.gz`).
  The payment cassettes moved from `transfer_drafts/` to `payments/` and
  match `/api/payments…`.

## [1.0.0]

### Changed

- **Renamed zazu to manza.** The shard, require path, namespace and repo all
  move; see the migration guide below. The version is not bumped here:
  `bin/release` writes 1.0.0 into `shard.yml` and `Manza::VERSION` at release.
- Requests send `Manza-Version` (was `Zazu-Version`) and the User-Agent is
  `manza-crystal/<version>` (was `zazu-crystal/<version>`).
- The cassette fetch script reads `getmanza/manza-ruby` and is pinned to
  `v1.0.0`; pass a tag or `latest` to override.
- Replay harness fixture variables are `MANZA_FIXTURE_*` (dev-only, no
  fallback).

### Deprecated

- `ZAZU_API_KEY`, `ZAZU_BASE_URL` and `ZAZU_API_VERSION` still work for all of
  1.x, but warn once per variable on stderr. Use the `MANZA_*` names.

### Migrating from zazu-crystal

| Before | After |
|--------|-------|
| shard `zazu` | shard `manza` |
| `github: getzazu/zazu-crystal` | `github: getmanza/manza-crystal` |
| `require "zazu"` | `require "manza"` |
| `Zazu::Client`, `Zazu::Error`, ... | `Manza::Client`, `Manza::Error`, ... |
| `ZAZU_API_KEY` | `MANZA_API_KEY` |
| `ZAZU_BASE_URL` | `MANZA_BASE_URL` |
| `ZAZU_API_VERSION` | `MANZA_API_VERSION` |
| `Zazu-Version` header | `Manza-Version` header |
| User-Agent `zazu-crystal/x` | User-Agent `manza-crystal/x` |
| `ZAZU_FIXTURE_*` (tests only) | `MANZA_FIXTURE_*` |

Error messages now start with `manza:` instead of `zazu:`.

## [0.3.0]

### Added

- `Zazu::ConflictError` (409), the 10th error class (`kind` `conflict`). A
  duplicate `client_reference` on a transfer draft raises it with
  `#payment_id` naming the existing draft. 400 now maps to the `validation`
  kind (lists return 400 for a malformed `limit`/`cursor`).
- `TransferDrafts#authorize(id, authorization_id, signature)` and
  `#decline(id, authorization_id, reason = nil)` for machine-authorized
  transfers. A blank signature raises `Zazu::ArgumentError` locally; the
  API would count it as a failed attempt.
- `TransferDrafts#create` documents the new optional `client_reference`.
- `Zazu::TransferAuthorization` — `signature_input`, `sign` and `payee_for`,
  the HMAC-SHA256 signer for authorization challenges, tested against the
  fixed vectors shared across SDKs.
- `Beneficiaries#create`, `#list_external_accounts`, `#get_external_account`
  and `#create_external_account`.
- `Zazu::Resources::PayeeTrustRequests` (`client.payee_trust_requests`) —
  `create(external_account_ids)` and `get(id)`.
- Docs for new pass-through fields: checkout session `customer_name`,
  `collect_billing_address`, `billing_address`, `settled_at`, `transaction`
  and the `clearing` status; payment link billing fields; customer
  `registration_number` / `vat_number` (and MA-only `tax_id` / `ice_number`).

### Changed

- Default base URL is now `https://ma.manza.finance` (Morocco production;
  South Africa is `https://za.manza.finance`). Cassettes are recorded
  against `https://ma.manza.dev`.
- The replay harness can compare a request body with `signature` removed
  (`with_replay(..., ignore_signature: true)`), used by the three
  authorize cassettes, and checks every cassette's recorded host.

## [0.2.1]

Version alignment: the whole SDK family now releases in lockstep with zazu-ruby. No functional changes since [0.1.0].

## [0.1.0]

Initial release.

### Added

- `Zazu::Client` built on stdlib `HTTP::Client` — zero runtime shard dependencies
- Resources: `accounts`, `beneficiaries`, `checkout_sessions`, `customers`, `entity`, `invoices`, `payment_links`, `transfer_drafts`, `webhook_endpoints`
- Cursor-based `Zazu::Page` with `#next` (max 100 records per page)
- `Zazu::Error` mirroring the shared SDK error taxonomy
- Cassette-replay test harness driven by the Ruby SDK's release tarball
