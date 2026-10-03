module Manza
  # Raised for invalid SDK arguments (e.g. a page limit above the cap).
  class ArgumentError < ::ArgumentError
  end

  # Raised by `Client.new` when the client can't be built.
  class ConfigurationError < Exception
  end

  # Wraps transport-level failures (timeouts, DNS, refused connections).
  class ConnectionError < Exception
  end

  # The API error envelope, mirroring the other Manza SDKs' hierarchy:
  # `{ "error": { "type": ..., "message": ..., "param": ... } }`. Match
  # on `#kind` instead of subclassing.
  class Error < Exception
    # HTTP status code of the failed response.
    getter status : Int32

    # One of: authentication, forbidden, not_found, validation, conflict,
    # rate_limit, server, api.
    getter kind : String

    # The API's `error.type` field.
    getter type : String?

    # The API's `error.param` field.
    getter param : String?

    # Value of the X-Request-Id response header.
    getter request_id : String?

    # Seconds to wait before retrying; only set for rate_limit (429).
    getter retry_after : Int32?

    # The full parsed response body.
    getter body : JSON::Any

    def initialize(message : String, @status : Int32, @kind : String, @type : String?,
                   @param : String?, @request_id : String?, @retry_after : Int32?, @body : JSON::Any)
      super(message)
    end

    def self.from_response(status : Int32, headers : HTTP::Headers, body : JSON::Any) : Error
      error_type = nil.as(String?)
      message = nil.as(String?)
      param = nil.as(String?)

      payload = body.as_h?.try(&.["error"]?).try(&.as_h?)
      if payload
        error_type = payload["type"]?.try(&.as_s?)
        message = payload["message"]?.try(&.as_s?)
        param = payload["param"]?.try(&.as_s?)
      end

      kind = kind_for(status)
      retry_after = headers["Retry-After"]?.try(&.to_i?) if status == 429
      message ||= HTTP::Status.new(status).description || "HTTP #{status}"
      request_id = headers["X-Request-Id"]?

      if status == 409
        payment_id = payload.try(&.["payment_id"]?).try(&.as_s?)
        return ConflictError.new(message, status, kind, error_type, param, request_id, retry_after, body, payment_id)
      end

      new(message, status, kind, error_type, param, request_id, retry_after, body)
    end

    def to_s(io : IO) : Nil
      if value = param
        io << "manza: " << message << " (" << status << ' ' << kind << ", param " << value << ')'
      else
        io << "manza: " << message << " (" << status << ' ' << kind << ')'
      end
    end

    private def self.kind_for(status : Int32) : String
      case status
      when 401      then "authentication"
      when 403      then "forbidden"
      when 404      then "not_found"
      when 400, 422 then "validation"
      when 409      then "conflict"
      when 429      then "rate_limit"
      else               status >= 500 ? "server" : "api"
      end
    end
  end

  # 409 — the request conflicts with an existing resource (`kind`
  # "conflict"). For a duplicate `client_reference` on a transfer draft
  # (`type` "duplicate_client_reference"), `#payment_id` names the draft
  # that already holds it.
  class ConflictError < Error
    # The API's `error.payment_id` field.
    getter payment_id : String?

    def initialize(message : String, status : Int32, kind : String, type : String?,
                   param : String?, request_id : String?, retry_after : Int32?, body : JSON::Any,
                   @payment_id : String? = nil)
      super(message, status, kind, type, param, request_id, retry_after, body)
    end
  end
end
