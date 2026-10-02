# Changelog

All notable changes to `zazu-crystal` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
