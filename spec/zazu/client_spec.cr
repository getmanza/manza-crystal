require "../spec_helper"

describe Zazu::Client do
  it "requires an API key" do
    original = ENV["ZAZU_API_KEY"]?
    ENV.delete("ZAZU_API_KEY")
    begin
      expect_raises(Zazu::ConfigurationError, /missing API key/) do
        Zazu::Client.new
      end
    ensure
      ENV["ZAZU_API_KEY"] = original if original
    end
  end

  it "validates the list limit" do
    client = Zazu::Client.new(api_key: "test", base_url: "http://127.0.0.1:1")

    expect_raises(Zazu::ArgumentError, /cannot exceed/) do
      client.beneficiaries.list(limit: Zazu::Page::MAX_PER_PAGE + 1)
    end
  end

  it "defaults to the Manza production host" do
    Zazu::Client::DEFAULT_BASE_URL.should eq("https://ma.manza.finance")
  end

  describe "error mapping" do
    it "maps 400 to a validation error" do
      body = %({"error":{"type":"invalid_request","message":"limit is malformed","param":"limit"}})
      with_stub(400, body) do |stub|
        error = expect_raises(Zazu::Error) { stub.client.accounts.list }
        error.status.should eq(400)
        error.kind.should eq("validation")
        error.param.should eq("limit")
        error.should_not be_a(Zazu::ConflictError)
      end
    end

    it "maps 409 to ConflictError carrying payment_id" do
      body = %({"error":{"type":"duplicate_client_reference","message":"exists","payment_id":"pay_1"}})
      with_stub(409, body) do |stub|
        error = expect_raises(Zazu::ConflictError) { stub.client.transfer_drafts.create(amount: "10.00") }
        error.kind.should eq("conflict")
        error.type.should eq("duplicate_client_reference")
        error.payment_id.should eq("pay_1")
        error.is_a?(Zazu::Error).should be_true
      end
    end

    it "leaves payment_id nil when the 409 carries none" do
      with_stub(409, %({"error":{"type":"conflict","message":"nope"}})) do |stub|
        error = expect_raises(Zazu::ConflictError) { stub.client.transfer_drafts.create(amount: "10.00") }
        error.payment_id.should be_nil
      end
    end
  end

  describe "TransferDrafts#decline" do
    it "omits reason when absent" do
      with_stub(200) do |stub|
        stub.client.transfer_drafts.decline("draft_1", "auth_1")
        stub.last_resource.should eq("/api/transfer_drafts/draft_1/decline")
        stub.last_body.should eq(%({"authorization_id":"auth_1"}))
      end
    end

    it "sends reason, after authorization_id, when given" do
      with_stub(200) do |stub|
        stub.client.transfer_drafts.decline("draft_1", "auth_1", "Not ours")
        stub.last_body.should eq(%({"authorization_id":"auth_1","reason":"Not ours"}))
      end
    end
  end
end
