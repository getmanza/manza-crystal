require "../spec_helper"
require "../../examples/transfer_authorizer/src/routing"

private def route(status : String, reason : String? = nil) : String
  TransferAuthorizer::Routing.describe(JSON.parse({"status" => status, "refusal_reason" => reason}.to_json))
end

describe TransferAuthorizer::Routing do
  describe ".describe" do
    it "says the challenge went to the authorizer when it is pending" do
      route("pending").should contain("challenge sent")
    end

    it "explains every create-time refusal reason in words" do
      expected = {
        "untrusted_payee"      => "bank details are not trusted",
        "unrestricted_api_key" => "key A has no IP allowlist",
        "over_new_payee_limit" => "limit per transfer to a new payee",
        "over_transfer_limit"  => "over the limit per transfer",
        "over_daily_limit"     => "limit per 24 hours",
        "currency_mismatch"    => "not the enrolled currency",
        "suspended"            => "is suspended",
        "secret_expired"       => "secret has expired",
      }
      TransferAuthorizer::Routing::REFUSAL_REASONS.keys.sort.should eq(expected.keys.sort)

      expected.each do |reason, words|
        line = route("refused", reason)
        ["approvers", "refused", reason, words].each { |part| line.should contain(part) }
      end
    end

    it "points at the docs for a reason it does not know" do
      line = route("refused", "something_new")
      line.should contain("something_new")
      line.should contain("transfer authorization docs")
    end

    it "says no authorizer was enrolled when there is no authorization" do
      TransferAuthorizer::Routing.describe(nil).should contain("no transfer authorizer")
      TransferAuthorizer::Routing.describe(JSON::Any.new(nil)).should contain("no transfer authorizer")
    end
  end
end
