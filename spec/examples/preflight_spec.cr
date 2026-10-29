require "../spec_helper"
require "../../examples/transfer_authorizer/src/preflight"

# Drives the example's preflight against a RouteStub answering the
# documented responses (ported from manza-ruby's
# spec/examples/preflight_spec.rb). No cassette: each failure is a stubbed
# response.
module PreflightSpec
  ACCOUNT_ID     = "01958e51-7c5a-7000-8000-000000000013"
  BENEFICIARY_ID = "01958e51-7c5a-7000-8000-000000000015"
  ENDPOINT_ID    = "01958e51-7c5a-7000-8000-000000000020"
  NOW            = Time.utc(2026, 10, 20, 12)

  class Setup
    getter stub : RouteStub
    getter env : Hash(String, String)
    getter authorizer : Hash(String, String?)
    getter endpoint : Hash(String, String)
    getter payee : Hash(String, String | Bool)

    def initialize(@stub : RouteStub)
      @env = {
        "MANZA_BASE_URL"           => stub.url,
        "MANZA_CREATOR_API_KEY"    => "key-a",
        "MANZA_AUTHORIZER_API_KEY" => "key-b",
        "MANZA_AUTHORIZER_SECRET"  => "whsec_example",
        "MANZA_ACCOUNT_ID"         => ACCOUNT_ID,
        "MANZA_BENEFICIARY_ID"     => BENEFICIARY_ID,
      }
      @authorizer = {
        "status" => "active", "suspension_reason" => nil, "currency_code" => "MAD", "per_transfer_limit" => "1000.0",
        "daily_limit" => "5000.0", "daily_authorized_total" => "100.0", "secret_expires_at" => "2027-01-18T00:00:00Z",
        "webhook_endpoint_id" => ENDPOINT_ID, "enrolled_at" => "2026-10-01T08:30:00Z",
      } of String => String?
      @endpoint = {"id" => ENDPOINT_ID, "url" => "https://authorizer.example.com/", "status" => "active"}
      @payee = {"id" => "01958e51-7c5a-7000-8000-000000000014", "default" => true, "trusted" => true} of String => String | Bool
      @overrides = {} of String => RouteStub::Reply
    end

    # Answers `GET path` with `reply` instead of the default response.
    def override(path : String, reply : RouteStub::Reply) : Nil
      @overrides[path] = reply
    end

    def run(amount : String = "10.00") : {Bool, String}
      install
      io = IO::Memory.new
      ok = TransferAuthorizer::Preflight.new(env: env, amount: amount, out: io, now: NOW).run
      {ok, io.to_s}
    end

    private def install : Nil
      beneficiary = {"id" => BENEFICIARY_ID, "external_accounts" => [payee]}
      {
        "/api/entity"                           => {"id" => "e1", "name" => "Acme"}.to_json,
        "/api/transfer_authorizer"              => authorizer.to_json,
        "/api/accounts/#{ACCOUNT_ID}"           => {"id" => ACCOUNT_ID, "currency_code" => "MAD"}.to_json,
        "/api/webhook_endpoints/#{ENDPOINT_ID}" => endpoint.to_json,
        "/api/beneficiaries/#{BENEFICIARY_ID}"  => beneficiary.to_json,
      }.each do |path, body|
        stub.on("GET", path, @overrides[path]? || RouteStub::Reply.new(200, body))
      end
    end
  end

  def self.error(status : Int32, type : String) : RouteStub::Reply
    RouteStub::Reply.new(status, {"error" => {"type" => type, "message" => "refused"}}.to_json)
  end

  def self.failures(output : String) : Array(String)
    output.lines.select(&.starts_with?("✗"))
  end

  def self.warnings(output : String) : Array(String)
    output.lines.select(&.starts_with?("!"))
  end

  def self.with_setup(& : Setup ->)
    with_route_stub { |stub| yield Setup.new(stub) }
  end
end

private def with_setup(& : PreflightSpec::Setup ->)
  PreflightSpec.with_setup { |setup| yield setup }
end

private def failures(output : String) : Array(String)
  PreflightSpec.failures(output)
end

private def api_error(status : Int32, type : String) : RouteStub::Reply
  PreflightSpec.error(status, type)
end

private def should_contain_all(line : String?, *parts : String)
  line.should_not be_nil
  parts.each { |part| line.to_s.should contain(part) }
end

describe TransferAuthorizer::Preflight do
  it "passes every step when the setup is complete, reading with the right key" do
    with_setup do |s|
      ok, output = s.run

      ok.should be_true
      failures(output).should be_empty
      output.lines.count(&.starts_with?("✓")).should eq(9)

      s.stub.requests.each do |request|
        key = request.path == "/api/transfer_authorizer" ? "key-b" : "key-a"
        request.headers["Authorization"].should eq("Bearer #{key}")
      end
    end
  end

  it "fails when a key is missing" do
    with_setup do |s|
      s.env["MANZA_AUTHORIZER_API_KEY"] = ""
      ok, output = s.run

      ok.should be_false
      should_contain_all(failures(output).first?, "MANZA_AUTHORIZER_API_KEY")
      s.stub.requests.should be_empty
    end
  end

  it "fails when the account or beneficiary id is missing" do
    with_setup do |s|
      s.env["MANZA_BENEFICIARY_ID"] = ""
      ok, output = s.run

      ok.should be_false
      should_contain_all(failures(output).first?, "MANZA_BENEFICIARY_ID")
      s.stub.requests.should be_empty
    end
  end

  it "fails when the amount is not a decimal, and runs the other checks" do
    with_setup do |s|
      ok, output = s.run(amount: "ten")

      ok.should be_false
      failures(output).size.should eq(1)
      should_contain_all(failures(output).first?, %("ten"), "10.00")
      output.should contain("✓ transfer authorizer is active")
      output.should_not contain("limit per transfer and")
    end
  end

  it "fails when the amount is not positive" do
    %w[-5 0 1/2 1e2].each do |amount|
      with_setup do |s|
        _, output = s.run(amount: amount)

        should_contain_all(failures(output).first?, amount.inspect, "positive")
      end
    end
  end

  it "stops before any request on a missing key, even with a bad amount" do
    with_setup do |s|
      s.env["MANZA_CREATOR_API_KEY"] = ""
      _, output = s.run(amount: "0")

      failures(output).size.should eq(2)
      s.stub.requests.should be_empty
    end
  end

  it "fails when both keys are the same" do
    with_setup do |s|
      s.env["MANZA_AUTHORIZER_API_KEY"] = "key-a"
      _, output = s.run

      should_contain_all(failures(output).first?, "different")
    end
  end

  it "fails when key A cannot reach the entity" do
    with_setup do |s|
      s.override("/api/entity", api_error(401, "authentication_error"))
      _, output = s.run

      should_contain_all(failures(output).first?, "key A", "MANZA_CREATOR_API_KEY")
    end
  end

  it "fails when no authorizer is enrolled" do
    with_setup do |s|
      s.override("/api/transfer_authorizer", api_error(404, "not_found_error"))
      _, output = s.run

      should_contain_all(failures(output).first?, "no transfer authorizer is enrolled", "Transfer approval")
    end
  end

  it "fails when key B cannot read the authorizer" do
    with_setup do |s|
      s.override("/api/transfer_authorizer", api_error(403, "insufficient_scope"))
      _, output = s.run

      should_contain_all(failures(output).first?, "key B", "insufficient_scope", "transfers:authorize")
    end
  end

  it "fails when key A cannot read the account" do
    with_setup do |s|
      s.override("/api/accounts/#{PreflightSpec::ACCOUNT_ID}", api_error(403, "insufficient_scope"))
      _, output = s.run

      should_contain_all(failures(output).first?, "key A", "accounts:read")
    end
  end

  it "fails when key A cannot read the enrolled webhook endpoint" do
    with_setup do |s|
      s.override("/api/webhook_endpoints/#{PreflightSpec::ENDPOINT_ID}", api_error(403, "insufficient_scope"))
      _, output = s.run

      should_contain_all(failures(output).first?, "key A", "webhook_endpoints:read")
    end
  end

  it "fails when key A cannot read the beneficiary" do
    with_setup do |s|
      s.override("/api/beneficiaries/#{PreflightSpec::BENEFICIARY_ID}", api_error(404, "not_found_error"))
      _, output = s.run

      should_contain_all(failures(output).first?, "key A", "MANZA_BENEFICIARY_ID")
    end
  end

  it "fails once, on the authorizer line, when the secret has expired" do
    with_setup do |s|
      s.authorizer.merge!({"status" => "suspended", "suspension_reason" => "secret_expired",
                           "secret_expires_at" => "2026-10-19T00:00:00Z"})
      _, output = s.run

      failures(output).size.should eq(1)
      should_contain_all(failures(output).first?, "suspended (secret_expired)", "rotates the secret")
    end
  end

  it "fails when the enrolled webhook endpoint was deleted" do
    with_setup do |s|
      s.override("/api/webhook_endpoints/#{PreflightSpec::ENDPOINT_ID}", api_error(404, "not_found_error"))
      _, output = s.run

      should_contain_all(failures(output).first?, "was deleted", "enrol")
    end
  end

  it "fails with the suspension reason and its fix" do
    with_setup do |s|
      s.authorizer.merge!({"status" => "suspended", "suspension_reason" => "endpoint_disabled"})
      _, output = s.run

      should_contain_all(failures(output).first?, "suspended (endpoint_disabled)", "re-enable")
    end
  end

  it "fails when the account's currency is not the enrolled one" do
    with_setup do |s|
      s.override("/api/accounts/#{PreflightSpec::ACCOUNT_ID}",
        RouteStub::Reply.new(200, {"id" => PreflightSpec::ACCOUNT_ID, "currency_code" => "ZAR"}.to_json))
      _, output = s.run

      should_contain_all(failures(output).first?, "ZAR", "MAD")
    end
  end

  it "fails when the secret expires within 7 days" do
    with_setup do |s|
      s.authorizer["secret_expires_at"] = "2026-10-23T00:00:00Z"
      _, output = s.run

      should_contain_all(failures(output).first?, "secret expires", "rotate")
    end
  end

  it "fails when the signing secret is not set" do
    with_setup do |s|
      s.env["MANZA_AUTHORIZER_SECRET"] = ""
      _, output = s.run

      should_contain_all(failures(output).first?, "MANZA_AUTHORIZER_SECRET")
    end
  end

  it "fails when the enrolled webhook endpoint is disabled" do
    with_setup do |s|
      s.endpoint["status"] = "disabled"
      _, output = s.run

      should_contain_all(failures(output).first?, "disabled", "enable", "if the authorizer stays suspended")
    end
  end

  it "warns when the endpoint is on a URL that changes when the tunnel restarts" do
    with_setup do |s|
      s.endpoint["url"] = "https://abc123.ngrok-free.app/"
      ok, output = s.run

      ok.should be_true
      should_contain_all(PreflightSpec.warnings(output).first?, "ngrok-free.app", "reserved domain")
    end
  end

  it "does not warn for a host that only ends with a tunnel domain's name" do
    with_setup do |s|
      s.endpoint["url"] = "https://notngrok-free.app/"
      _, output = s.run

      PreflightSpec.warnings(output).should be_empty
    end
  end

  it "shows the amount it compared, without rounding it" do
    with_setup do |s|
      _, output = s.run(amount: "1000.001")

      should_contain_all(failures(output).first?, "1000.001 is over the limit per transfer (1000.00)")
    end
  end

  it "fails when the amount is over the limit per transfer" do
    with_setup do |s|
      _, output = s.run(amount: "1500.00")

      should_contain_all(failures(output).first?, "limit per transfer")
    end
  end

  it "fails when the amount does not fit in the last 24 hours' room" do
    with_setup do |s|
      s.authorizer["daily_authorized_total"] = "4995.0"
      _, output = s.run

      should_contain_all(failures(output).first?, "24 hours")
    end
  end

  it "warns that a new payee needs the toggle, which the API does not show" do
    with_setup do |s|
      s.payee["trusted"] = false
      ok, output = s.run

      ok.should be_true
      should_contain_all(PreflightSpec.warnings(output).first?, "not trusted yet", "Approve transfers to new payees", "IP allowlist")
    end
  end

  it "fails when the beneficiary has no default bank account" do
    with_setup do |s|
      s.payee["default"] = false
      _, output = s.run

      should_contain_all(failures(output).first?, "default bank account")
    end
  end
end
