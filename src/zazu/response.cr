module Zazu
  # A successful (2xx) API response.
  class Response
    # HTTP status code.
    getter status : Int32

    # Value of the X-Request-Id response header.
    getter request_id : String?

    # The parsed JSON body, as-is from the API (snake_case keys).
    # Non-JSON bodies parse to `nil`; the raw bytes stay on `#raw`.
    getter body : JSON::Any

    # The unparsed response body.
    getter raw : String

    def initialize(@status : Int32, @request_id : String?, @body : JSON::Any, @raw : String)
    end
  end
end
