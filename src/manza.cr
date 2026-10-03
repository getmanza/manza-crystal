# The Crystal SDK for the Manza API.
#
# Response bodies are returned as-is from the API — snake_case keys as
# `JSON::Any`, no typed models. The same shape ships across every Manza
# SDK (Ruby, TypeScript, Python, Go, ...) so the cassette contract is
# one-to-one.
require "http/client"
require "json"
require "uri"

require "./manza/env"
require "./manza/errors"
require "./manza/response"
require "./manza/page"
require "./manza/transfer_authorization"
require "./manza/resources/base"
require "./manza/resources/accounts"
require "./manza/resources/beneficiaries"
require "./manza/resources/checkout_sessions"
require "./manza/resources/customers"
require "./manza/resources/entity"
require "./manza/resources/invoices"
require "./manza/resources/payee_trust_requests"
require "./manza/resources/payment_links"
require "./manza/resources/transfer_drafts"
require "./manza/resources/webhook_endpoints"
require "./manza/client"

module Manza
  # The SDK version, sent in the User-Agent header.
  VERSION = "0.3.0"
end
