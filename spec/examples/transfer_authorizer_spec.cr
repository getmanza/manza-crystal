require "../spec_helper"
require "../../examples/transfer_authorizer/src/authorizer"

# Drives the example's authorizer with a signed copy of the documented
# `payment.authorization_requested` payload (the same one manza-ruby's
# spec/examples/transfer_authorizer_spec.rb uses), against a RouteStub
# standing in for the API. No cassette: these are not SDK resources.
module TransferAuthorizerSpec
  extend self

  SECRET           = "whsec_example_authorizer_secret"
  DRAFT_ID         = "01958e51-7c5a-7000-8000-000000000012"
  AUTHORIZATION_ID = "01958e51-7c5a-7000-8000-000000000011"
  NONCE            = "9f86d081884c7d659a2feaa0c55ad015"
  AUTHORIZE        = "/api/payments/#{DRAFT_ID}/authorize"
  DECLINE          = "/api/payments/#{DRAFT_ID}/decline"
  SIGNATURE_INPUT  = "manza.transfer-authorization.v1|01958e51-7c5a-7000-8000-000000000012|" \
                     "9f86d081884c7d659a2feaa0c55ad015|2500.0|ZAR|01958e51-7c5a-7000-8000-000000000013|" \
                     "ext:01958e51-7c5a-7000-8000-000000000014|po_8812"

  LEDGER_ENTRY = {
    payment_id:    DRAFT_ID,
    amount:        "2500.0",
    currency_code: "ZAR",
    account_id:    "01958e51-7c5a-7000-8000-000000000013",
    payee:         "ext:01958e51-7c5a-7000-8000-000000000014",
  }

  def payload : Hash(String, JSON::Any)
    JSON.parse(<<-JSON).as_h
      {
        "event": "payment.authorization_requested",
        "event_id": "01958e51-7c5a-7000-8000-000000000010",
        "created_at": "2026-10-01T12:00:00Z",
        "data": {
          "authorization": {
            "id": "#{AUTHORIZATION_ID}",
            "nonce": "#{NONCE}",
            "expires_at": "2026-10-01T13:00:00Z",
            "signature_version": "manza.transfer-authorization.v1"
          },
          "payment": {
            "id": "#{DRAFT_ID}",
            "amount": "2500.0",
            "currency_code": "ZAR",
            "account_id": "01958e51-7c5a-7000-8000-000000000013",
            "payee": "ext:01958e51-7c5a-7000-8000-000000000014",
            "beneficiary_id": "01958e51-7c5a-7000-8000-000000000015",
            "external_account_id": "01958e51-7c5a-7000-8000-000000000014",
            "destination_account_id": null,
            "payment_reference": "INV-2026-001",
            "client_reference": "po_8812",
            "payee_trusted": false
          },
          "signature_input": "#{SIGNATURE_INPUT}"
        }
      }
      JSON
  end

  # The payload with `data.payment[key]` replaced (or removed for nil).
  def payload_with_payment(key : String, value : JSON::Any?) : String
    event = payload
    payment = event["data"].as_h["payment"].as_h
    value ? (payment[key] = value) : payment.delete(key)
    event.to_json
  end

  def expected_signature : String
    input = Manza::TransferAuthorization.signature_input(
      LEDGER_ENTRY[:payment_id], NONCE, LEDGER_ENTRY[:amount], LEDGER_ENTRY[:currency_code],
      LEDGER_ENTRY[:account_id], LEDGER_ENTRY[:payee], "po_8812"
    )
    Manza::TransferAuthorization.sign(SECRET, input)
  end

  def ok(body : String = %({"status":"processing"})) : RouteStub::Reply
    RouteStub::Reply.new(200, body)
  end

  class Harness
    getter stub : RouteStub
    getter log = IO::Memory.new
    getter ledger : TransferAuthorizer::Ledger

    def initialize(@stub : RouteStub, allow_new_payees : Bool = true)
      @path = File.tempname("ledger", ".json")
      @ledger = TransferAuthorizer::Ledger.new(@path)
      @app = TransferAuthorizer::App.new(
        client: Manza::Client.new(api_key: "key-b", base_url: stub.url),
        secret: SECRET,
        ledger: @ledger,
        executor: ->(job : Proc(Nil)) { job.call; nil },
        log: @log,
        ledger_wait: 0.seconds,
        retry_delay: 0.seconds,
        allow_new_payees: allow_new_payees
      )
    end

    def record(amount : String = LEDGER_ENTRY[:amount]) : Nil
      @ledger.record("po_8812", **LEDGER_ENTRY.merge(amount: amount))
    end

    # POSTs `body` to the handler through a built HTTP::Server::Context and
    # returns the status it answered.
    def deliver(body : String, signature : String? = nil, timestamp : String = Time.utc.to_unix.to_s) : Int32
      headers = HTTP::Headers{
        "Content-Type"      => "application/json",
        "X-Manza-Signature" => signature || Manza::Webhook.sign(body, timestamp, SECRET),
        "X-Manza-Timestamp" => timestamp,
      }
      response = HTTP::Server::Response.new(IO::Memory.new)
      context = HTTP::Server::Context.new(HTTP::Request.new("POST", "/", headers, body), response)
      @app.call(context)
      response.status_code
    end

    def deliver_example : Int32
      deliver(TransferAuthorizerSpec.payload.to_json)
    end

    def cleanup : Nil
      [@path, "#{@path}.lock"].each { |file| File.delete(file) if File.exists?(file) }
    end
  end

  def with_harness(allow_new_payees : Bool = true, & : Harness ->)
    with_route_stub do |stub|
      harness = Harness.new(stub, allow_new_payees)
      begin
        yield harness
      ensure
        harness.cleanup
      end
    end
  end
end

include TransferAuthorizerSpec

describe TransferAuthorizer::App do
  describe "with a matching ledger entry" do
    it "signs from the ledger and authorizes with key B" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, ok(%({"id":"#{DRAFT_ID}","status":"processing"})))

        h.deliver_example.should eq(200)

        requests = h.stub.requests
        requests.size.should eq(1)
        requests.first.path.should eq(AUTHORIZE)
        requests.first.headers["Authorization"].should eq("Bearer key-b")
        JSON.parse(requests.first.body).should eq(JSON.parse({
          "authorization_id" => AUTHORIZATION_ID, "signature" => expected_signature,
        }.to_json))
        %w[verified ledger\ match signed authorized].each { |line| h.log.to_s.should contain(line) }
      end
    end

    it "logs the API error type and request id when authorize fails" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, RouteStub::Reply.new(
          422, %({"error":{"message":"Signature does not match","type":"invalid_signature"}}),
          HTTP::Headers{"X-Request-Id" => "req_123"}))

        h.deliver_example.should eq(200)

        h.log.to_s.should contain("invalid_signature")
        h.log.to_s.should contain("req_123")
      end
    end

    it "logs both signature inputs and does not authorize when the webhook's differs from the ledger's" do
      with_harness do |h|
        h.record
        event = TransferAuthorizerSpec.payload
        event["data"].as_h["signature_input"] = JSON::Any.new("something-else")

        h.deliver(event.to_json)

        h.stub.requests.should be_empty
        h.log.to_s.should contain("something-else")
        h.log.to_s.should contain(SIGNATURE_INPUT)
      end
    end

    it "retries authorize after a transient failure" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, RouteStub::Reply.new(503), ok)

        h.deliver_example

        h.stub.requests_to("POST", AUTHORIZE).size.should eq(2)
        h.log.to_s.should contain("retrying")
        h.log.to_s.should contain("authorized")
      end
    end

    it "gives up after three attempts" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, RouteStub::Reply.new(503))

        h.deliver_example

        h.stub.requests_to("POST", AUTHORIZE).size.should eq(3)
        h.log.to_s.should contain("API error Manza::Error server")
      end
    end

    it "retries authorize while the API answers authorization_busy" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, RouteStub::Reply.new(409, %({"error":{"type":"authorization_busy"}})), ok)

        h.deliver_example

        h.stub.requests_to("POST", AUTHORIZE).size.should eq(2)
        h.log.to_s.should contain("retrying")
        h.log.to_s.should contain("authorized")
      end
    end

    it "does not retry another conflict" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, RouteStub::Reply.new(409, %({"error":{"type":"already_answered"}})))

        h.deliver_example

        h.stub.requests_to("POST", AUTHORIZE).size.should eq(1)
        h.log.to_s.should contain("API error Manza::ConflictError conflict")
      end
    end

    it "does not retry a validation error" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, RouteStub::Reply.new(422, %({"error":{"type":"invalid_signature"}})))

        h.deliver_example

        h.stub.requests_to("POST", AUTHORIZE).size.should eq(1)
      end
    end

    it "logs that a new payee will be trusted on authorize" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, ok)

        h.deliver_example

        h.log.to_s.should contain("new payee ext:01958e51-7c5a-7000-8000-000000000014, will be trusted on authorize")
      end
    end

    it "does not log a new payee when the payee is already trusted" do
      with_harness do |h|
        h.record
        h.stub.on("POST", AUTHORIZE, ok)

        h.deliver(payload_with_payment("payee_trusted", JSON::Any.new(true)))

        h.log.to_s.should_not contain("new payee")
      end
    end

    describe "with ALLOW_NEW_PAYEES=false" do
      it "declines a webhook that does not say whether the payee is trusted" do
        with_harness(allow_new_payees: false) do |h|
          h.record
          h.stub.on("POST", DECLINE, ok("{}"))

          h.deliver(payload_with_payment("payee_trusted", nil))

          declines = h.stub.requests_to("POST", DECLINE)
          declines.size.should eq(1)
          body = JSON.parse(declines.first.body)
          body["authorization_id"].should eq(AUTHORIZATION_ID)
          body["reason"].as_s.should contain("new payee")
        end
      end

      it "declines a transfer to a payee that is not trusted yet" do
        with_harness(allow_new_payees: false) do |h|
          h.record
          h.stub.on("POST", DECLINE, ok(%({"id":"#{AUTHORIZATION_ID}","status":"declined"})))

          h.deliver_example

          declines = h.stub.requests_to("POST", DECLINE)
          declines.size.should eq(1)
          JSON.parse(declines.first.body)["reason"].as_s.should contain("new payee")
          h.stub.requests_to("POST", AUTHORIZE).should be_empty
          h.log.to_s.should contain("declined")
        end
      end

      it "authorizes a trusted payee" do
        with_harness(allow_new_payees: false) do |h|
          h.record
          h.stub.on("POST", AUTHORIZE, ok)

          h.deliver(payload_with_payment("payee_trusted", JSON::Any.new(true)))

          h.stub.requests_to("POST", AUTHORIZE).size.should eq(1)
        end
      end
    end
  end

  describe "with a ledger mismatch" do
    it "declines with a reason naming the field" do
      with_harness do |h|
        h.record(amount: "25000.0")
        h.stub.on("POST", DECLINE, ok(%({"id":"#{AUTHORIZATION_ID}","status":"declined"})))

        h.deliver_example.should eq(200)

        declines = h.stub.requests_to("POST", DECLINE)
        declines.size.should eq(1)
        body = JSON.parse(declines.first.body)
        body["authorization_id"].should eq(AUTHORIZATION_ID)
        body["reason"].as_s.should contain("amount")
        h.stub.requests_to("POST", AUTHORIZE).should be_empty
        h.log.to_s.should contain("declined")
      end
    end
  end

  describe "without a ledger entry" do
    it "declines a client_reference this authorizer never issued" do
      with_harness do |h|
        h.stub.on("POST", DECLINE, ok("{}"))

        h.deliver_example

        declines = h.stub.requests_to("POST", DECLINE)
        declines.size.should eq(1)
        JSON.parse(declines.first.body)["reason"].as_s.should contain("po_8812")
      end
    end
  end

  describe "with a bad signature" do
    it "answers 401 and calls nothing" do
      with_harness do |h|
        h.deliver(TransferAuthorizerSpec.payload.to_json, signature: "0" * 64).should eq(401)

        h.stub.requests.should be_empty
        h.log.to_s.should contain("rejected a delivery")
      end
    end
  end

  describe "with a body over the size limit" do
    it "answers 413 without reading it all and calls nothing" do
      with_harness do |h|
        body = %({"event":"test.ping","pad":"#{"x" * (1024 * 1024)}"})
        h.deliver(body).should eq(413)

        h.stub.requests.should be_empty
        h.log.to_s.should contain("rejected a delivery")
      end
    end
  end

  describe "with a signed body that is not a JSON object" do
    it "answers 401 and calls nothing" do
      with_harness do |h|
        h.deliver("[]").should eq(401)

        h.stub.requests.should be_empty
      end
    end
  end

  describe "with another event" do
    it "answers 200 and calls nothing" do
      with_harness do |h|
        h.deliver(%({"event":"test.ping","event_id":"0199a1b2-0000-7000-8000-000000000010"})).should eq(200)

        h.stub.requests.should be_empty
        h.log.to_s.should contain("ignoring test.ping")
      end
    end
  end
end
