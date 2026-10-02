# Mirror of spec/support/fixture_ids.rb in zazu-ruby (and cassette_test.go
# in zazu-go). The placeholders must exactly match what VCR scrubbed the
# real staging UUIDs to when the cassettes were recorded — otherwise the
# request URI won't match.
FIXTURE_IDS = {
  "ZAZU_FIXTURE_ACCOUNT_ID"                  => "fixture-account-id",
  "ZAZU_FIXTURE_TRANSACTION_ID"              => "fixture-transaction-id",
  "ZAZU_FIXTURE_CUSTOMER_ID"                 => "fixture-customer-id",
  "ZAZU_FIXTURE_DELETABLE_CUSTOMER_ID"       => "fixture-deletable-customer-id",
  "ZAZU_FIXTURE_INVOICE_ID"                  => "fixture-invoice-id",
  "ZAZU_FIXTURE_DELETABLE_INVOICE_ID"        => "fixture-deletable-invoice-id",
  "ZAZU_FIXTURE_PAYMENT_LINK_ID"             => "fixture-payment-link-id",
  "ZAZU_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID" => "fixture-cancellable-payment-link-id",
  "ZAZU_FIXTURE_WEBHOOK_ID"                  => "fixture-webhook-id",
  "ZAZU_FIXTURE_ENABLED_WEBHOOK_ID"          => "fixture-enabled-webhook-id",
  "ZAZU_FIXTURE_DISABLED_WEBHOOK_ID"         => "fixture-disabled-webhook-id",
  "ZAZU_FIXTURE_DELETABLE_WEBHOOK_ID"        => "fixture-deletable-webhook-id",
  "ZAZU_FIXTURE_CHECKOUT_SESSION_ID"         => "fixture-checkout-session-id",
  "ZAZU_FIXTURE_BENEFICIARY_ID"              => "fixture-beneficiary-id",
  "ZAZU_FIXTURE_TRANSFER_DRAFT_ID"           => "fixture-transfer-draft-id",
  # The discovered beneficiary's default bank account, marked a
  # trusted payee once by hand so machine-authorized drafts can
  # target it.
  "ZAZU_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID" => "fixture-trusted-external-account-id",
  "ZAZU_FIXTURE_CREATED_BENEFICIARY_ID"      => "fixture-created-beneficiary-id",
  "ZAZU_FIXTURE_EXTERNAL_ACCOUNT_ID"         => "fixture-external-account-id",
  # Not an ID, but fresh per seed (bank account numbers are unique
  # per entity) and scrubbed the same way.
  "ZAZU_FIXTURE_NEW_ACCOUNT_NUMBER"     => "fixture-new-account-number",
  "ZAZU_FIXTURE_PAYEE_TRUST_REQUEST_ID" => "fixture-payee-trust-request-id",
  # client_reference is unique per entity, so these are fresh per seed too.
  "ZAZU_FIXTURE_CLIENT_REFERENCE"               => "fixture-client-reference",
  "ZAZU_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE"  => "fixture-authorizable-client-reference",
  "ZAZU_FIXTURE_AUTHORIZABLE_DRAFT_ID"          => "fixture-authorizable-draft-id",
  "ZAZU_FIXTURE_DECLINABLE_DRAFT_ID"            => "fixture-declinable-draft-id",
  "ZAZU_FIXTURE_BAD_SIGNATURE_DRAFT_ID"         => "fixture-bad-signature-draft-id",
  "ZAZU_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"  => "fixture-authorizable-authorization-id",
  "ZAZU_FIXTURE_DECLINABLE_AUTHORIZATION_ID"    => "fixture-declinable-authorization-id",
  "ZAZU_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID" => "fixture-bad-signature-authorization-id",
  # One-time nonce from the authorization webhook. Only needed while
  # recording; it never appears in a request or response.
  "ZAZU_FIXTURE_AUTHORIZABLE_NONCE" => "fixture-authorizable-nonce",
}

def fixture_id(env_var : String) : String
  FIXTURE_IDS[env_var]? || raise "unknown fixture env var #{env_var.inspect} — add it to FIXTURE_IDS"
end
