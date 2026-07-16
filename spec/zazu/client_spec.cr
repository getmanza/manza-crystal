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
end
