require "crypto/subtle"
require "http/headers"
require "openssl/hmac"

module Manza
  # Verifies incoming webhook deliveries. Pure functions — no HTTP.
  #
  # Every delivery carries `X-Manza-Signature` (hex HMAC-SHA256 of
  # "<timestamp>.<raw body>" under the endpoint's signing secret) and
  # `X-Manza-Timestamp` (Unix seconds, fresh on every attempt). The
  # legacy `X-Zazu-*` names carry the same values.
  #
  # Pass the **raw request body**, never re-serialized JSON:
  #
  # ```
  # event = Manza::Webhook.construct_event(
  #   context.request.body.try(&.gets_to_end) || "", context.request.headers, signing_secret
  # )
  # event["event"] # => "payment.authorization_requested"
  # ```
  module Webhook
    DEFAULT_TOLERANCE = 300.seconds

    # Hex HMAC-SHA256 of "<timestamp>.<payload>". For tests and local tools.
    def self.sign(payload : String, timestamp : String | Int, secret : String) : String
      OpenSSL::HMAC.hexdigest(:sha256, secret, "#{timestamp}.#{payload}")
    end

    # True when the signature matches (constant time) and the timestamp is
    # within `tolerance` of `now`. `tolerance: nil` skips the timestamp
    # check (for replaying a captured delivery in a local tool or test,
    # never on a live endpoint). Never raises on bad input; returns false.
    def self.verify?(payload : String?, signature : String?, timestamp : String | Int | Nil, secret : String?,
                     tolerance : Time::Span? = DEFAULT_TOLERANCE, now : Time = Time.utc) : Bool
      signature_matches?(payload, signature, timestamp, secret) && timestamp_fresh?(timestamp, tolerance, now)
    end

    # Reads `X-Manza-Signature` / `X-Manza-Timestamp` (any case, falling
    # back to `X-Zazu-*`), verifies them, and returns the parsed event,
    # always a JSON object. Raises `Manza::ArgumentError` when a header is
    # missing, the signature does not match, the timestamp is outside
    # tolerance, or the body is not a JSON object.
    def self.construct_event(payload : String, headers : HTTP::Headers, secret : String,
                             tolerance : Time::Span? = DEFAULT_TOLERANCE, now : Time = Time.utc) : JSON::Any
      signature = header(headers, "Signature")
      timestamp = header(headers, "Timestamp")

      unless signature_matches?(payload, signature, timestamp, secret)
        raise Manza::ArgumentError.new("invalid webhook signature")
      end
      unless timestamp_fresh?(timestamp, tolerance, now)
        raise Manza::ArgumentError.new("webhook timestamp outside tolerance")
      end

      event = begin
        JSON.parse(payload)
      rescue JSON::ParseException
        raise Manza::ArgumentError.new("webhook payload is not JSON")
      end
      raise Manza::ArgumentError.new("webhook payload is not a JSON object") unless event.as_h?

      event
    end

    private def self.signature_matches?(payload : String?, signature : String?, timestamp : String | Int | Nil,
                                        secret : String?) : Bool
      return false if payload.nil? || signature.nil? || timestamp.nil? || secret.nil? || secret.empty?
      return false unless parse_timestamp(timestamp)

      Crypto::Subtle.constant_time_compare(sign(payload, timestamp, secret), signature)
    end

    private def self.timestamp_fresh?(timestamp : String | Int | Nil, tolerance : Time::Span?, now : Time) : Bool
      return true if tolerance.nil?

      seconds = parse_timestamp(timestamp)
      !seconds.nil? && (now.to_unix - seconds).abs <= tolerance.total_seconds
    end

    private def self.parse_timestamp(timestamp : String | Int | Nil) : Int64?
      timestamp.to_s.to_i64?
    end

    private def self.header(headers : HTTP::Headers, suffix : String) : String
      value = headers["X-Manza-#{suffix}"]?.presence || headers["X-Zazu-#{suffix}"]?.presence
      value || raise Manza::ArgumentError.new("missing X-Manza-#{suffix} header")
    end
  end
end
