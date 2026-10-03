# Mirror of spec/support/fixture_ids.rb in manza-ruby (and cassette_test.go
# in manza-go). The placeholders must exactly match what VCR scrubbed the
# real staging UUIDs to when the cassettes were recorded — otherwise the
# request URI won't match.
FIXTURE_IDS = {
  "MANZA_FIXTURE_ACCOUNT_ID"                  => "fixture-account-id",
  "MANZA_FIXTURE_TRANSACTION_ID"              => "fixture-transaction-id",
  "MANZA_FIXTURE_CUSTOMER_ID"                 => "fixture-customer-id",
  "MANZA_FIXTURE_DELETABLE_CUSTOMER_ID"       => "fixture-deletable-customer-id",
  "MANZA_FIXTURE_INVOICE_ID"                  => "fixture-invoice-id",
  "MANZA_FIXTURE_DELETABLE_INVOICE_ID"        => "fixture-deletable-invoice-id",
  "MANZA_FIXTURE_PAYMENT_LINK_ID"             => "fixture-payment-link-id",
  "MANZA_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID" => "fixture-cancellable-payment-link-id",
  "MANZA_FIXTURE_WEBHOOK_ID"                  => "fixture-webhook-id",
  "MANZA_FIXTURE_ENABLED_WEBHOOK_ID"          => "fixture-enabled-webhook-id",
  "MANZA_FIXTURE_DISABLED_WEBHOOK_ID"         => "fixture-disabled-webhook-id",
  "MANZA_FIXTURE_DELETABLE_WEBHOOK_ID"        => "fixture-deletable-webhook-id",
  "MANZA_FIXTURE_CHECKOUT_SESSION_ID"         => "fixture-checkout-session-id",
  "MANZA_FIXTURE_BENEFICIARY_ID"              => "fixture-beneficiary-id",
  "MANZA_FIXTURE_TRANSFER_DRAFT_ID"           => "fixture-transfer-draft-id",
  # The discovered beneficiary's default bank account, marked a
  # trusted payee once by hand so machine-authorized drafts can
  # target it.
  "MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID" => "fixture-trusted-external-account-id",
  "MANZA_FIXTURE_CREATED_BENEFICIARY_ID"      => "fixture-created-beneficiary-id",
  "MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID"         => "fixture-external-account-id",
  # Not an ID, but fresh per seed (bank account numbers are unique
  # per entity) and scrubbed the same way.
  "MANZA_FIXTURE_NEW_ACCOUNT_NUMBER"     => "fixture-new-account-number",
  "MANZA_FIXTURE_PAYEE_TRUST_REQUEST_ID" => "fixture-payee-trust-request-id",
  # client_reference is unique per entity, so these are fresh per seed too.
  "MANZA_FIXTURE_CLIENT_REFERENCE"               => "fixture-client-reference",
  "MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE"  => "fixture-authorizable-client-reference",
  "MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID"          => "fixture-authorizable-draft-id",
  "MANZA_FIXTURE_DECLINABLE_DRAFT_ID"            => "fixture-declinable-draft-id",
  "MANZA_FIXTURE_BAD_SIGNATURE_DRAFT_ID"         => "fixture-bad-signature-draft-id",
  "MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"  => "fixture-authorizable-authorization-id",
  "MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID"    => "fixture-declinable-authorization-id",
  "MANZA_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID" => "fixture-bad-signature-authorization-id",
  # One-time nonce from the authorization webhook. Only needed while
  # recording; it never appears in a request or response.
  "MANZA_FIXTURE_AUTHORIZABLE_NONCE" => "fixture-authorizable-nonce",
}

def fixture_id(env_var : String) : String
  FIXTURE_IDS[env_var]? || raise "unknown fixture env var #{env_var.inspect} — add it to FIXTURE_IDS"
end
