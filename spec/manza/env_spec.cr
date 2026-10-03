require "../spec_helper"

describe Manza::Env do
  it "reads the MANZA_ name without warning" do
    with_clean_env do |io|
      ENV["MANZA_API_KEY"] = "sk_manza"
      Manza::Env.fetch("API_KEY").should eq("sk_manza")
      io.to_s.should be_empty
    end
  end

  it "prefers MANZA_ over ZAZU_ and stays silent" do
    with_clean_env do |io|
      ENV["MANZA_API_KEY"] = "sk_manza"
      ENV["ZAZU_API_KEY"] = "sk_zazu"
      Manza::Env.fetch("API_KEY").should eq("sk_manza")
      io.to_s.should be_empty
    end
  end

  it "falls back to ZAZU_ with a deprecation warning" do
    with_clean_env do |io|
      ENV["ZAZU_API_KEY"] = "sk_zazu"
      Manza::Env.fetch("API_KEY").should eq("sk_zazu")
      io.to_s.should contain("ZAZU_API_KEY is deprecated")
      io.to_s.should contain("MANZA_API_KEY")
    end
  end

  it "warns only once per variable" do
    with_clean_env do |io|
      ENV["ZAZU_API_KEY"] = "sk_zazu"
      ENV["ZAZU_BASE_URL"] = "https://example.test"
      3.times { Manza::Env.fetch("API_KEY") }
      Manza::Env.fetch("BASE_URL")
      io.to_s.scan(/ZAZU_API_KEY is deprecated/).size.should eq(1)
      io.to_s.scan(/ZAZU_BASE_URL is deprecated/).size.should eq(1)
    end
  end

  it "returns nil when neither is set" do
    with_clean_env do |io|
      Manza::Env.fetch("API_KEY").should be_nil
      io.to_s.should be_empty
    end
  end
end
