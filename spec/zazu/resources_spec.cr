require "../spec_helper"

# Mirror of zazu-go's resources_test.go (itself a mirror of zazu-ruby's
# spec/zazu/resources/*_spec.rb) — same cassettes, same assertions, per
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

      account_id = fixture_id("ZAZU_FIXTURE_ACCOUNT_ID")
      client.accounts.get(account_id)
      client.accounts.list_transactions(account_id)
      client.accounts.get_transaction(account_id, fixture_id("ZAZU_FIXTURE_TRANSACTION_ID"))
    end
  end
end

describe "Customers" do
  it "lists and gets" do
    with_replay("customers/list", "customers/get") do |client|
      client.customers.list

      response = client.customers.get(fixture_id("ZAZU_FIXTURE_CUSTOMER_ID"))
      response.body["id"].as_s?.should_not be_nil
    end
  end
end

describe "Invoices" do
  it "lists and gets" do
    with_replay("invoices/list", "invoices/get") do |client|
      page = client.invoices.list
      page.data.should_not be_empty

      client.invoices.get(fixture_id("ZAZU_FIXTURE_INVOICE_ID"))
    end
  end
end

describe "PaymentLinks" do
  it "lists, creates, and cancels" do
    with_replay("payment_links/list", "payment_links/get", "payment_links/create", "payment_links/cancel") do |client|
      client.payment_links.list

      response = client.payment_links.create(
        account_id: fixture_id("ZAZU_FIXTURE_ACCOUNT_ID"),
        amount: "100.00",
        title: "SDK fixture",
        description: "Created by zazu-ruby fixture spec",
        link_type: "single"
      )
      response.status.should eq(201)

      client.payment_links.cancel(fixture_id("ZAZU_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID"))
    end
  end
end

describe "CheckoutSessions" do
  it "gets" do
    with_replay("checkout_sessions/get") do |client|
      response = client.checkout_sessions.get(fixture_id("ZAZU_FIXTURE_CHECKOUT_SESSION_ID"))
      response.body["id"].as_s?.should_not be_nil
    end
  end
end

describe "WebhookEndpoints" do
  it "lists and gets" do
    with_replay("webhook_endpoints/list", "webhook_endpoints/get") do |client|
      client.webhook_endpoints.list
      client.webhook_endpoints.get(fixture_id("ZAZU_FIXTURE_WEBHOOK_ID"))
    end
  end
end

describe "TransferDrafts" do
  it "creates (routing into in-app approval) and gets" do
    with_replay("transfer_drafts/create", "transfer_drafts/get") do |client|
      response = client.transfer_drafts.create(
        account_id: fixture_id("ZAZU_FIXTURE_ACCOUNT_ID"),
        beneficiary_id: fixture_id("ZAZU_FIXTURE_BENEFICIARY_ID"),
        amount: "150.00",
        payment_reference: "SDK fixture"
      )
      response.status.should eq(201)
      # Awaiting in-app approval — the API never executes a transfer.
      response.body["status"].as_s?.should eq("requested")
      response.body["transfer"].raw.should be_nil

      got = client.transfer_drafts.get(fixture_id("ZAZU_FIXTURE_TRANSFER_DRAFT_ID"))
      got.body["status"].as_s?.should_not be_nil
    end
  end
end

describe "Beneficiaries" do
  it "lists (with embedded external_accounts) and gets" do
    with_replay("beneficiaries/list", "beneficiaries/get") do |client|
      page = client.beneficiaries.list
      page.data.should_not be_empty
      page.data.first["external_accounts"].as_a?.should_not be_nil

      response = client.beneficiaries.get(fixture_id("ZAZU_FIXTURE_BENEFICIARY_ID"))
      response.body["id"].as_s?.should_not be_nil
    end
  end
end
