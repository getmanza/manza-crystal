require "../spec_helper"

# Fixed test vector, shared by every SDK in the family (see manza-ruby's
# spec/manza/webhook_spec.rb). Each verifier must accept exactly this
# delivery. The signature was computed independently with:
#
#   printf '%s' '1767225600.<payload>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'
describe Manza::Webhook do
  secret = "whsec_test_vector_secret"
  timestamp = "1767225600"
  payload = %({"event":"test.ping","event_id":"0199a1b2-0000-7000-8000-000000000010"})
  signature = "970fdd13680015f73dbd172884498c6fd1e07d5b5c41aae081272598607fea75"
  now = Time.unix(1_767_225_600)

  describe ".sign" do
    it "signs the shared vector" do
      Manza::Webhook.sign(payload, timestamp, secret).should eq(signature)
    end

    it "accepts an integer timestamp" do
      Manza::Webhook.sign(payload, 1_767_225_600, secret).should eq(signature)
    end
  end

  describe ".verify?" do
    it "accepts the shared vector" do
      Manza::Webhook.verify?(payload, signature, timestamp, secret, now: now).should be_true
    end

    it "accepts the shared vector with named arguments" do
      Manza::Webhook.verify?(payload: payload, signature: signature, timestamp: timestamp, secret: secret, now: now)
        .should be_true
    end

    it "rejects a wrong secret" do
      Manza::Webhook.verify?(payload, signature, timestamp, "whsec_other", now: now).should be_false
    end

    it "rejects a tampered payload" do
      Manza::Webhook.verify?(payload.sub("ping", "pong"), signature, timestamp, secret, now: now).should be_false
    end

    it "rejects a signature of the wrong length without raising" do
      Manza::Webhook.verify?(payload, "abc", timestamp, secret, now: now).should be_false
    end

    it "rejects a timestamp 301 seconds old" do
      Manza::Webhook.verify?(payload, signature, timestamp, secret, now: now + 301.seconds).should be_false
    end

    it "rejects a timestamp 301 seconds in the future" do
      Manza::Webhook.verify?(payload, signature, timestamp, secret, now: now - 301.seconds).should be_false
    end

    it "accepts a timestamp exactly at the tolerance" do
      Manza::Webhook.verify?(payload, signature, timestamp, secret, now: now + 300.seconds).should be_true
    end

    it "skips the timestamp check with tolerance: nil" do
      Manza::Webhook.verify?(payload, signature, timestamp, secret, tolerance: nil, now: now + 1.day).should be_true
    end

    it "rejects a non-numeric timestamp" do
      Manza::Webhook.verify?(payload, signature, "yesterday", secret, tolerance: nil).should be_false
    end

    it "rejects nil inputs" do
      Manza::Webhook.verify?(payload, nil, timestamp, secret, now: now).should be_false
      Manza::Webhook.verify?(payload, signature, nil, secret, now: now).should be_false
      Manza::Webhook.verify?(nil, signature, timestamp, secret, now: now).should be_false
      Manza::Webhook.verify?(payload, signature, timestamp, nil, now: now).should be_false
    end

    it "rejects an empty secret, even with a signature made under it" do
      forged = Manza::Webhook.sign(payload, timestamp, "")

      Manza::Webhook.verify?(payload, forged, timestamp, "", now: now).should be_false
    end
  end

  describe ".construct_event" do
    it "returns the parsed event for X-Manza-* headers" do
      headers = HTTP::Headers{"X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp}

      event = Manza::Webhook.construct_event(payload, headers, secret, now: now)

      event.should eq(JSON.parse(%({"event":"test.ping","event_id":"0199a1b2-0000-7000-8000-000000000010"})))
    end

    it "reads mixed-case header names" do
      headers = HTTP::Headers{"x-MANZA-signature" => signature, "X-manza-Timestamp" => timestamp}

      Manza::Webhook.construct_event(payload, headers, secret, now: now)["event"].should eq("test.ping")
    end

    it "falls back to X-Zazu-* headers" do
      headers = HTTP::Headers{"X-Zazu-Signature" => signature, "X-Zazu-Timestamp" => timestamp}

      Manza::Webhook.construct_event(payload, headers, secret, now: now)["event"].should eq("test.ping")
    end

    it "prefers X-Manza-* over X-Zazu-*" do
      headers = HTTP::Headers{
        "X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp,
        "X-Zazu-Signature" => "0" * 64, "X-Zazu-Timestamp" => "1",
      }

      Manza::Webhook.construct_event(payload, headers, secret, now: now)["event"].should eq("test.ping")
    end

    it "raises on a missing signature header" do
      expect_raises(Manza::ArgumentError, "missing X-Manza-Signature header") do
        Manza::Webhook.construct_event(payload, HTTP::Headers{"X-Manza-Timestamp" => timestamp}, secret, now: now)
      end
    end

    it "raises on a missing timestamp header" do
      expect_raises(Manza::ArgumentError, "missing X-Manza-Timestamp header") do
        Manza::Webhook.construct_event(payload, HTTP::Headers{"X-Manza-Signature" => signature}, secret, now: now)
      end
    end

    it "raises on an empty header as if it were missing" do
      headers = HTTP::Headers{"X-Manza-Signature" => "", "X-Manza-Timestamp" => timestamp}

      expect_raises(Manza::ArgumentError, "missing X-Manza-Signature header") do
        Manza::Webhook.construct_event(payload, headers, secret, now: now)
      end
    end

    it "raises on a bad signature" do
      headers = HTTP::Headers{"X-Manza-Signature" => "0" * 64, "X-Manza-Timestamp" => timestamp}

      expect_raises(Manza::ArgumentError, "invalid webhook signature") do
        Manza::Webhook.construct_event(payload, headers, secret, now: now)
      end
    end

    it "raises on a stale timestamp" do
      headers = HTTP::Headers{"X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp}

      expect_raises(Manza::ArgumentError, "webhook timestamp outside tolerance") do
        Manza::Webhook.construct_event(payload, headers, secret, now: now + 301.seconds)
      end
    end

    it "accepts a stale timestamp with tolerance: nil" do
      headers = HTTP::Headers{"X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp}

      event = Manza::Webhook.construct_event(payload, headers, secret, tolerance: nil, now: now + 301.seconds)

      event["event"].should eq("test.ping")
    end

    it "raises on a body that is not JSON" do
      body = "not json"
      headers = HTTP::Headers{
        "X-Manza-Signature" => Manza::Webhook.sign(body, timestamp, secret), "X-Manza-Timestamp" => timestamp,
      }

      expect_raises(Manza::ArgumentError, "webhook payload is not JSON") do
        Manza::Webhook.construct_event(body, headers, secret, now: now)
      end
    end

    it "raises on an empty secret" do
      headers = HTTP::Headers{
        "X-Manza-Signature" => Manza::Webhook.sign(payload, timestamp, ""), "X-Manza-Timestamp" => timestamp,
      }

      expect_raises(Manza::ArgumentError, "invalid webhook signature") do
        Manza::Webhook.construct_event(payload, headers, "", now: now)
      end
    end

    it "raises on a body that is valid JSON but not an object" do
      ["[]", "null", "42"].each do |body|
        headers = HTTP::Headers{
          "X-Manza-Signature" => Manza::Webhook.sign(body, timestamp, secret), "X-Manza-Timestamp" => timestamp,
        }

        expect_raises(Manza::ArgumentError, "webhook payload is not a JSON object") do
          Manza::Webhook.construct_event(body, headers, secret, now: now)
        end
      end
    end
  end
end
