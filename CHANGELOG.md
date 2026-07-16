# Changelog

All notable changes to `zazu-crystal` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

Initial release.

### Added

- `Zazu::Client` built on stdlib `HTTP::Client` — zero runtime shard dependencies
- Resources: `accounts`, `beneficiaries`, `checkout_sessions`, `customers`, `entity`, `invoices`, `payment_links`, `transfer_drafts`, `webhook_endpoints`
- Cursor-based `Zazu::Page` with `#next` (max 100 records per page)
- `Zazu::Error` mirroring the shared SDK error taxonomy
- Cassette-replay test harness driven by the Ruby SDK's release tarball
