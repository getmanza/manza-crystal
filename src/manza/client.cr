module Manza
  # The SDK entry point. Resources hang off it as getters.
  #
  # ```
  # client = Manza::Client.new(api_key: "sk_live_...")
  # page = client.accounts.list
  # ```
  class Client
    DEFAULT_BASE_URL = "https://ma.manza.finance"
    DEFAULT_TIMEOUT  = 30.seconds

    @api_key : String
    @base_url : String
    @api_version : String?
    @timeout : Time::Span

    getter accounts : Resources::Accounts { Resources::Accounts.new(self) }
    getter beneficiaries : Resources::Beneficiaries { Resources::Beneficiaries.new(self) }
    getter checkout_sessions : Resources::CheckoutSessions { Resources::CheckoutSessions.new(self) }
    getter customers : Resources::Customers { Resources::Customers.new(self) }
    getter entity : Resources::Entity { Resources::Entity.new(self) }
    getter invoices : Resources::Invoices { Resources::Invoices.new(self) }
    getter payee_trust_requests : Resources::PayeeTrustRequests { Resources::PayeeTrustRequests.new(self) }
    getter payment_links : Resources::PaymentLinks { Resources::PaymentLinks.new(self) }
    getter transfer_drafts : Resources::TransferDrafts { Resources::TransferDrafts.new(self) }
    getter webhook_endpoints : Resources::WebhookEndpoints { Resources::WebhookEndpoints.new(self) }

    # Builds a client. An API key is required — pass `api_key` or set
    # MANZA_API_KEY. `base_url` defaults to MANZA_BASE_URL or
    # https://ma.manza.finance (Morocco; South Africa is
    # https://za.manza.finance); `api_version` pins the Manza-Version request
    # header (default: MANZA_API_VERSION). The pre-1.0 ZAZU_* names still work
    # but warn once.
    def initialize(api_key : String? = nil, base_url : String? = nil,
                   api_version : String? = nil, timeout : Time::Span = DEFAULT_TIMEOUT)
      key = api_key || Env.fetch("API_KEY")
      if key.nil? || key.empty?
        raise ConfigurationError.new("missing API key: pass api_key or set MANZA_API_KEY")
      end

      @api_key = key
      @base_url = (base_url || Env.fetch("BASE_URL") || DEFAULT_BASE_URL).rstrip('/')
      @api_version = api_version || Env.fetch("API_VERSION")
      @timeout = timeout
    end

    # Performs an HTTP request against the API. Non-2xx responses raise
    # `Manza::Error`; transport failures raise `Manza::ConnectionError`.
    # `body` (when non-nil) must already be JSON-encoded.
    def request(method : String, path : String, params : URI::Params? = nil, body : String? = nil) : Response
      target = "/" + path.lstrip('/')
      if params && !params.empty?
        target += "?#{params}"
      end

      headers = HTTP::Headers{
        "Authorization" => "Bearer #{@api_key}",
        "User-Agent"    => "manza-crystal/#{VERSION}",
        "Accept"        => "application/json",
      }
      headers["Content-Type"] = "application/json" if body
      if version = @api_version
        headers["Manza-Version"] = version
      end

      raw = perform(method, target, headers, body)
      parsed = parse_json(raw.body)

      unless (200..299).includes?(raw.status_code)
        raise Error.from_response(raw.status_code, raw.headers, parsed)
      end

      Response.new(raw.status_code, raw.headers["X-Request-Id"]?, parsed, raw.body)
    end

    # :nodoc:
    def get(path : String, params : URI::Params? = nil) : Response
      request("GET", path, params: params)
    end

    # :nodoc:
    def post(path : String, body : String? = nil) : Response
      request("POST", path, body: body)
    end

    # :nodoc:
    def patch(path : String, body : String? = nil) : Response
      request("PATCH", path, body: body)
    end

    # :nodoc:
    def delete(path : String) : Response
      request("DELETE", path)
    end

    private def perform(method : String, target : String, headers : HTTP::Headers, body : String?) : HTTP::Client::Response
      http = HTTP::Client.new(URI.parse(@base_url))
      http.connect_timeout = @timeout
      http.read_timeout = @timeout
      http.write_timeout = @timeout

      begin
        http.exec(method.upcase, target, headers: headers, body: body)
      rescue ex : IO::Error | OpenSSL::Error
        raise ConnectionError.new(ex.message || ex.class.name)
      ensure
        http.close
      end
    end

    private def parse_json(raw : String) : JSON::Any
      return JSON::Any.new(nil) if raw.empty?

      # Non-JSON bodies parse to nil; the raw bytes stay on Response#raw.
      JSON.parse(raw)
    rescue JSON::ParseException
      JSON::Any.new(nil)
    end
  end
end
