require "../spec_helper"

# Mirror of manza-go's resources_test.go (itself a mirror of manza-ruby's
# spec/manza/resources/*_spec.rb) — same cassettes, same assertions, per
# the cross-language SDK contract.

describe "Entity" do
  it "gets the current entity" do
    with_replay("entity/get") do |client|
      response = client.entity.get
      response.body["id"].as_s?.should_not be_nil
    end
  end
end

describe "Accounts" do
  it "lists, gets, and reads transactions" do
    with_replay("accounts/list", "accounts/get", "accounts/list_transactions", "accounts/get_transaction") do |client|
      page = client.accounts.list
      page.data.should_not be_empty

      account_id = fixture_id("MANZA_FIXTURE_ACCOUNT_ID")
      client.accounts.get(account_id)
      client.accounts.list_transactions(account_id)
      client.accounts.get_transaction(account_id, fixture_id("MANZA_FIXTURE_TRANSACTION_ID"))
    end
  end
end

describe "Customers" do
  it "lists and gets" do
    with_replay("customers/list", "customers/get") do |client|
      client.customers.list

      response = client.customers.get(fixture_id("MANZA_FIXTURE_CUSTOMER_ID"))
      response.body["id"].as_s?.should_not be_nil
    end
  end
end

describe "Invoices" do
  it "lists and gets" do
    with_replay("invoices/list", "invoices/get") do |client|
      page = client.invoices.list
      page.data.should_not be_empty

      client.invoices.get(fixture_id("MANZA_FIXTURE_INVOICE_ID"))
    end
  end
end

describe "PaymentLinks" do
  it "lists, creates, and cancels" do
    with_replay("payment_links/list", "payment_links/get", "payment_links/create", "payment_links/cancel") do |client|
      client.payment_links.list

      response = client.payment_links.create(
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        amount: "100.00",
        title: "SDK fixture",
        description: "Created by zazu-ruby fixture spec",
        link_type: "single"
      )
      response.status.should eq(201)

      client.payment_links.cancel(fixture_id("MANZA_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID"))
    end
  end
end

describe "CheckoutSessions" do
  it "creates" do
    with_replay("checkout_sessions/create") do |client|
      response = client.checkout_sessions.create(
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        amount: "100.00",
        success_url: "https://example.com/zazu-fixture-success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "https://example.com/zazu-fixture-cancel",
        description: "Created by zazu-ruby fixture spec",
        customer_email: "fixture@example.com",
        metadata: {order_id: "ORD-FIXTURE"}
      )
      response.status.should eq(201)
      response.body["id"].as_s?.should_not be_nil
      response.body["url"].as_s?.should_not be_nil
      response.body["status"].as_s?.should eq("open")
    end
  end

  it "gets" do
    with_replay("checkout_sessions/get") do |client|
      response = client.checkout_sessions.get(fixture_id("MANZA_FIXTURE_CHECKOUT_SESSION_ID"))
      response.body["id"].as_s?.should_not be_nil
    end
  end
end

describe "WebhookEndpoints" do
  it "lists and gets" do
    with_replay("webhook_endpoints/list", "webhook_endpoints/get") do |client|
      client.webhook_endpoints.list
      client.webhook_endpoints.get(fixture_id("MANZA_FIXTURE_WEBHOOK_ID"))
    end
  end
end

describe "Payments" do
  it "creates a draft carrying the client_reference" do
    with_replay("payments/create") do |client|
      response = client.payments.create(
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        beneficiary_id: fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"),
        amount: "10.00",
        payment_reference: "SDK fixture",
        internal_notes: "[zazu-ruby-fixture] create spec - do not approve",
        client_reference: fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE")
      )
      response.status.should eq(201)
      # Awaiting approval — the API never executes a transfer itself.
      response.body["status"].as_s?.should eq("requested")
      response.body["client_reference"].as_s?.should eq(fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE"))
      # Inside the envelope: the challenge went to the authorizer.
      response.body["authorization"]["status"].as_s?.should eq("pending")
      response.body["transfer"].raw.should be_nil
    end
  end

  it "raises ConflictError naming the existing draft on a duplicate client_reference" do
    with_replay("payments/create_duplicate") do |client|
      error = expect_raises(Manza::ConflictError) do
        client.payments.create(
          account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
          beneficiary_id: fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"),
          amount: "10.00",
          client_reference: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE")
        )
      end
      error.status.should eq(409)
      error.kind.should eq("conflict")
      error.type.should eq("duplicate_client_reference")
      error.payment_id.should eq(fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID"))
    end
  end

  it "gets a draft" do
    with_replay("payments/get") do |client|
      got = client.payments.get(fixture_id("MANZA_FIXTURE_TRANSFER_DRAFT_ID"))
      got.body["id"].as_s?.should_not be_nil
      got.body.as_h.has_key?("status").should be_true
      got.body.as_h.has_key?("transfer").should be_true
    end
  end

  it "gets a draft refused at create time, with its refusal_reason" do
    with_replay("payments/get_refused") do |client|
      got = client.payments.get(fixture_id("MANZA_FIXTURE_REFUSED_DRAFT_ID"))
      got.body["id"].as_s?.should eq(fixture_id("MANZA_FIXTURE_REFUSED_DRAFT_ID"))
      got.body["authorization"]["status"].as_s?.should eq("refused")
      got.body["authorization"]["refusal_reason"].as_s?.should eq("over_transfer_limit")
    end
  end

  it "refuses a blank signature locally, without calling the API" do
    # Nothing listens on port 1: reaching HTTP would raise ConnectionError.
    client = Manza::Client.new(api_key: "test", base_url: "http://127.0.0.1:1")

    expect_raises(Manza::ArgumentError, /signature/) do
      client.payments.authorize("draft", "auth", " ")
    end
    expect_raises(Manza::ArgumentError, /signature/) do
      client.payments.authorize("draft", "auth", "")
    end
  end

  it "raises ValidationError invalid_signature on a bad signature" do
    with_replay("payments/authorize_bad_signature", ignore_signature: true) do |client|
      error = expect_raises(Manza::Error) do
        client.payments.authorize(
          fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_DRAFT_ID"),
          fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID"),
          "0" * 64
        )
      end
      error.kind.should eq("validation")
      error.type.should eq("invalid_signature")
    end
  end

  it "raises forbidden same_key_forbidden when the creating key authorizes" do
    with_replay("payments/authorize_same_key", ignore_signature: true) do |client|
      error = expect_raises(Manza::Error) do
        client.payments.authorize(
          fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID"),
          fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
          "0" * 64
        )
      end
      error.kind.should eq("forbidden")
      error.type.should eq("same_key_forbidden")
    end
  end

  it "authorizes (executes) a draft" do
    with_replay("payments/authorize", ignore_signature: true) do |client|
      draft_id = fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID")
      input = Manza::TransferAuthorization.signature_input(
        draft_id,
        fixture_id("MANZA_FIXTURE_AUTHORIZABLE_NONCE"),
        "10.0",
        "MAD",
        fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        Manza::TransferAuthorization.payee_for(
          external_account_id: fixture_id("MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID")
        ),
        fixture_id("MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE")
      )

      response = client.payments.authorize(
        draft_id,
        fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
        Manza::TransferAuthorization.sign("replay-secret", input)
      )
      response.status.should eq(200)
      response.body["id"].as_s?.should eq(draft_id)
      response.body["authorization"]["status"].as_s?.should eq("authorized")
    end
  end

  # The fresh bank account was never trusted; with "Approve transfers to
  # new payees" on, the authorizer approves it and the signature trusts it.
  it "authorizes a draft to a new payee" do
    with_replay("payments/authorize_new_payee", ignore_signature: true) do |client|
      draft_id = fixture_id("MANZA_FIXTURE_NEW_PAYEE_DRAFT_ID")
      input = Manza::TransferAuthorization.signature_input(
        draft_id,
        fixture_id("MANZA_FIXTURE_NEW_PAYEE_NONCE"),
        "10.0",
        "MAD",
        fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        Manza::TransferAuthorization.payee_for(external_account_id: fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")),
        fixture_id("MANZA_FIXTURE_NEW_PAYEE_CLIENT_REFERENCE")
      )

      response = client.payments.authorize(
        draft_id,
        fixture_id("MANZA_FIXTURE_NEW_PAYEE_AUTHORIZATION_ID"),
        Manza::TransferAuthorization.sign("replay-secret", input)
      )
      response.status.should eq(200)
      response.body["id"].as_s?.should eq(draft_id)
      response.body["authorization"]["status"].as_s?.should eq("authorized")
    end
  end

  it "declines the challenge" do
    with_replay("payments/decline") do |client|
      response = client.payments.decline(
        fixture_id("MANZA_FIXTURE_DECLINABLE_DRAFT_ID"),
        fixture_id("MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID"),
        "SDK fixture"
      )
      response.status.should eq(200)
      response.body["id"].as_s?.should eq(fixture_id("MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID"))
      response.body["status"].as_s?.should eq("declined")
      response.body["declined_at"].as_s?.should_not be_nil
    end
  end
end

describe "TransferDrafts (deprecated)" do
  it "is the payments resource, so it calls /api/payments" do
    client = Manza::Client.new(api_key: "test", base_url: "http://127.0.0.1:1")

    client.transfer_drafts.should be(client.payments)
  end

  it "keeps the constant, naming the same class" do
    Manza::Resources::TransferDrafts.should eq(Manza::Resources::Payments)
  end

  it "replays the payments cassettes" do
    with_replay("payments/get") do |client|
      client.transfer_drafts.get(fixture_id("MANZA_FIXTURE_TRANSFER_DRAFT_ID")).status.should eq(200)
    end
  end
end

describe "TransferAuthorizer" do
  it "returns the enrolled authorizer's status, limits and usage" do
    with_replay("transfer_authorizer/get") do |client|
      response = client.transfer_authorizer.get
      response.status.should eq(200)
      response.body["status"].as_s?.should eq("active")
      response.body["suspension_reason"].raw.should be_nil
      response.body["currency_code"].as_s?.should eq("MAD")
      %w[per_transfer_limit daily_limit daily_authorized_total secret_expires_at webhook_endpoint_id enrolled_at].each do |key|
        response.body.as_h.has_key?(key).should be_true
      end
    end
  end

  it "raises not_found when no authorizer is enrolled" do
    body = %({"error":{"type":"not_found","message":"No transfer authorizer is enrolled"}})
    with_stub(404, body) do |stub|
      error = expect_raises(Manza::Error) { stub.client.transfer_authorizer.get }
      error.kind.should eq("not_found")
      stub.last_method.should eq("GET")
      stub.last_resource.should eq("/api/transfer_authorizer")
    end
  end
end

describe "Beneficiaries" do
  it "lists (with embedded external_accounts) and gets" do
    with_replay("beneficiaries/list", "beneficiaries/get") do |client|
      page = client.beneficiaries.list
      page.data.should_not be_empty
      page.data.first["external_accounts"].as_a?.should_not be_nil

      response = client.beneficiaries.get(fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"))
      response.body["id"].as_s?.should_not be_nil
    end
  end

  it "creates a beneficiary" do
    with_replay("beneficiaries/create") do |client|
      response = client.beneficiaries.create(
        beneficiary_type: "business",
        company_name: "Manza Fixture Beneficiary spec",
        email: "fixture-beneficiary-spec@example.com"
      )
      response.status.should eq(201)
      response.body["beneficiary_type"].as_s?.should eq("business")
      response.body["external_accounts"].as_a.should be_empty
    end
  end

  it "lists the beneficiary's bank accounts as a Page" do
    with_replay("beneficiaries/list_external_accounts") do |client|
      page = client.beneficiaries.list_external_accounts(fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID"))
      page.should be_a(Manza::Page)
      page.data.first["id"].as_s?.should eq(fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID"))
      page.data.first["account_number"].as_s?.should_not be_nil
      page.has_more.should be_false
    end
  end

  it "gets a single bank account" do
    with_replay("beneficiaries/get_external_account") do |client|
      response = client.beneficiaries.get_external_account(
        fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID"),
        fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")
      )
      response.body["id"].as_s?.should eq(fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID"))
      response.body.as_h.has_key?("default").should be_true
    end
  end

  # Recorded after the new-payee authorize: its signature trusted the payee.
  it "shows the new payee's bank account as trusted afterwards" do
    with_replay("beneficiaries/get_external_account_trusted") do |client|
      response = client.beneficiaries.get_external_account(
        fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID"),
        fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")
      )
      response.body["id"].as_s?.should eq(fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID"))
      response.body["trusted"].as_bool?.should be_true
    end
  end

  it "adds a bank account to the beneficiary" do
    with_replay("beneficiaries/create_external_account") do |client|
      response = client.beneficiaries.create_external_account(
        fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID"),
        account_number: fixture_id("MANZA_FIXTURE_NEW_ACCOUNT_NUMBER"),
        name: "Fixture Secondary Account"
      )
      response.status.should eq(201)
      response.body["name"].as_s?.should eq("Fixture Secondary Account")
      response.body["default"].as_bool?.should eq(false)
    end
  end
end

describe "PayeeTrustRequests" do
  it "files a pending trust request" do
    with_replay("payee_trust_requests/create") do |client|
      response = client.payee_trust_requests.create([fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")])
      response.status.should eq(201)
      response.body["status"].as_s?.should eq("pending")
      response.body["external_account_ids"].as_a.map(&.as_s).should eq([fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")])
    end
  end

  it "gets a trust request" do
    with_replay("payee_trust_requests/get") do |client|
      response = client.payee_trust_requests.get(fixture_id("MANZA_FIXTURE_PAYEE_TRUST_REQUEST_ID"))
      response.body["id"].as_s?.should eq(fixture_id("MANZA_FIXTURE_PAYEE_TRUST_REQUEST_ID"))
      response.body["resolved_at"].raw.should be_nil
    end
  end
end
