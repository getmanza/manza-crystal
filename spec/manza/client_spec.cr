require "../spec_helper"

describe Manza::Client do
  it "requires an API key" do
    with_clean_env do
      expect_raises(Manza::ConfigurationError, /set MANZA_API_KEY/) do
        Manza::Client.new
      end
    end
  end

  describe "environment" do
    it "reads MANZA_API_KEY, MANZA_BASE_URL and MANZA_API_VERSION" do
      with_clean_env do |io|
        ENV["MANZA_API_KEY"] = "sk_manza"
        ENV["MANZA_BASE_URL"] = "https://za.manza.finance/"
        ENV["MANZA_API_VERSION"] = "2026-10-01"
        client = Manza::Client.new
        client.@api_key.should eq("sk_manza")
        client.@base_url.should eq("https://za.manza.finance")
        client.@api_version.should eq("2026-10-01")
        io.to_s.should be_empty
      end
    end

    it "falls back to the ZAZU_* names with a warning each" do
      with_clean_env do |io|
        ENV["ZAZU_API_KEY"] = "sk_zazu"
        ENV["ZAZU_BASE_URL"] = "https://za.manza.finance"
        ENV["ZAZU_API_VERSION"] = "2026-09-01"
        client = Manza::Client.new
        client.@api_key.should eq("sk_zazu")
        client.@base_url.should eq("https://za.manza.finance")
        client.@api_version.should eq("2026-09-01")
        %w(ZAZU_API_KEY ZAZU_BASE_URL ZAZU_API_VERSION).each do |name|
          io.to_s.should contain("#{name} is deprecated")
        end
      end
    end

    it "warns once across several clients" do
      with_clean_env do |io|
        ENV["ZAZU_API_KEY"] = "sk_zazu"
        3.times { Manza::Client.new }
        io.to_s.scan(/ZAZU_API_KEY is deprecated/).size.should eq(1)
      end
    end

    it "sends the Manza-Version header and manza-crystal User-Agent" do
      with_stub(200) do |stub|
        client = Manza::Client.new(api_key: "k", base_url: stub.url, api_version: "2026-10-01")
        client.accounts.list
        stub.last_headers["Manza-Version"]?.should eq("2026-10-01")
        stub.last_headers["Zazu-Version"]?.should be_nil
        stub.last_headers["User-Agent"]?.should eq("manza-crystal/#{Manza::VERSION}")
      end
    end
  end

  it "validates the list limit" do
    client = Manza::Client.new(api_key: "test", base_url: "http://127.0.0.1:1")

    expect_raises(Manza::ArgumentError, /cannot exceed/) do
      client.beneficiaries.list(limit: Manza::Page::MAX_PER_PAGE + 1)
    end
  end

  it "defaults to the Manza production host" do
    Manza::Client::DEFAULT_BASE_URL.should eq("https://ma.manza.finance")
  end

  describe "error mapping" do
    it "maps 400 to a validation error" do
      body = %({"error":{"type":"invalid_request","message":"limit is malformed","param":"limit"}})
      with_stub(400, body) do |stub|
        error = expect_raises(Manza::Error) { stub.client.accounts.list }
        error.status.should eq(400)
        error.kind.should eq("validation")
        error.param.should eq("limit")
        error.should_not be_a(Manza::ConflictError)
      end
    end

    it "maps 409 to ConflictError carrying payment_id" do
      body = %({"error":{"type":"duplicate_client_reference","message":"exists","payment_id":"pay_1"}})
      with_stub(409, body) do |stub|
        error = expect_raises(Manza::ConflictError) { stub.client.transfer_drafts.create(amount: "10.00") }
        error.kind.should eq("conflict")
        error.type.should eq("duplicate_client_reference")
        error.payment_id.should eq("pay_1")
        error.is_a?(Manza::Error).should be_true
      end
    end

    it "leaves payment_id nil when the 409 carries none" do
      with_stub(409, %({"error":{"type":"conflict","message":"nope"}})) do |stub|
        error = expect_raises(Manza::ConflictError) { stub.client.transfer_drafts.create(amount: "10.00") }
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
