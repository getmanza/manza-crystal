# Changelog

All notable changes to `manza-crystal` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
