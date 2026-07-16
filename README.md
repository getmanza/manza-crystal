# zazu-crystal

Crystal SDK for the [Zazu](https://zazu.ma) API.

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
  payment_reference: "INV-000042"
)
```

## Response shape

Response bodies are returned as-is from the API — `snake_case` keys as
`JSON::Any`, no typed models. The same shape ships across every Zazu
SDK (Ruby, TypeScript, Python, Go, ...) so the cassette contract is
one-to-one.

## Pagination

List endpoints return a `Zazu::Page` (`data`, `has_more`, `next_cursor`)
with a `#next` method that fetches the following page, or `nil` on the
last one. Page size is capped at 100.

## Errors

Non-2xx responses raise `Zazu::Error` with `status`, `kind`
(`authentication`, `forbidden`, `not_found`, `validation`, `rate_limit`,
`server`, `api`), the API's `type`/`message`/`param`, the `request_id`,
and `retry_after` for 429s. Transport failures raise
`Zazu::ConnectionError`; a client misconfiguration (missing API key)
raises `Zazu::ConfigurationError`.

## Configuration

| Option | Env var | Default |
|--------|---------|---------|
| `api_key` | `ZAZU_API_KEY` | required |
| `base_url` | `ZAZU_BASE_URL` | `https://zazu.ma` |
| `api_version` (Zazu-Version header) | `ZAZU_API_VERSION` | unset |
| `timeout` | — | 30 seconds |

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
