# The Crystal SDK for the Zazu API.
#
# Response bodies are returned as-is from the API — snake_case keys as
# `JSON::Any`, no typed models. The same shape ships across every Zazu
# SDK (Ruby, TypeScript, Python, Go, ...) so the cassette contract is
# one-to-one.
require "http/client"
require "json"
require "uri"

require "./zazu/errors"
require "./zazu/response"
require "./zazu/page"
require "./zazu/resources/base"
require "./zazu/resources/accounts"
require "./zazu/resources/beneficiaries"
require "./zazu/resources/checkout_sessions"
require "./zazu/resources/customers"
require "./zazu/resources/entity"
require "./zazu/resources/invoices"
require "./zazu/resources/payment_links"
require "./zazu/resources/transfer_drafts"
require "./zazu/resources/webhook_endpoints"
require "./zazu/client"

module Zazu
  # The SDK version, sent in the User-Agent header.
  VERSION = "0.2.1"
end
