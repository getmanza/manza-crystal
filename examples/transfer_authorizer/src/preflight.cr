require "big"
require "uri"
require "../../../src/manza"

module TransferAuthorizer
  # Checks every setup step before you create a transfer, and says how to
  # fix the ones that fail. One line per check: ✓ passed, ✗ failed
  # (followed by the fix), ! a warning the API cannot settle.
  class Preflight
    SECRET_MIN_DAYS = 7
    # Hosts that hand out a new URL on every restart. An enrolled endpoint's
    # URL is locked, so the next restart breaks the authorizer.
    UNSTABLE_TUNNEL_HOSTS = %w[ngrok-free.app trycloudflare.com]
    SUSPENSION_FIXES      = {
      "member"             => "an approver suspended it: resume it in Settings → Developer → Transfer approval",
      "signature_failures" => "five invalid signatures in a row: fix the signing, then an approver resumes it in the app",
      "secret_expired"     => "an approver rotates the secret in the app (and resumes it if it stays suspended); " \
                          "set the new one as MANZA_AUTHORIZER_SECRET",
      "endpoint_disabled" => "re-enable the webhook endpoint (webhook_endpoints.enable), or enrol a new one if it was " \
                             "deleted; if it stays suspended, an approver resumes it in the app",
    }

    @amount : BigDecimal?
    @creator : Manza::Client?
    @authorizer_client : Manza::Client?

    def initialize(@env : Hash(String, String) = ENV.to_h, amount : String = "10.00", @out : IO = STDOUT,
                   @now : Time = Time.utc)
      @raw_amount = amount
      # BigDecimal compares the API's decimal strings exactly. Plain decimals
      # only: create_transfer.cr sends the string as is, so "1/2" or "1e2"
      # would not mean the same to the API.
      parsed = amount.matches?(/\A\d+(?:\.\d+)?\z/) ? BigDecimal.new(amount) : nil
      @amount = parsed && parsed > 0 ? parsed : nil
      @ok = true
    end

    # Prints one line per step; true when no step failed.
    def run : Bool
      fail_step("amount #{@raw_amount.inspect} is not a positive decimal", "pass an amount like 10.00 or 250.00") unless @amount
      return @ok unless keys?

      creator_reaches_entity
      authorizer = enrolled_authorizer
      if authorizer
        currency_matches(authorizer)
        # An expired secret already failed the authorizer line, with its fix.
        secret_fresh(authorizer) unless string(authorizer, "suspension_reason") == "secret_expired"
      end
      secret_set
      if authorizer
        endpoint_enabled(authorizer)
        if amount = @amount
          amount_within_limits(authorizer, amount)
        end
      end
      payee_trusted
      @ok
    end

    # 1. Both keys (and the ids the other steps read) are set, the keys different.
    private def keys? : Bool
      missing = %w[MANZA_CREATOR_API_KEY MANZA_AUTHORIZER_API_KEY MANZA_ACCOUNT_ID MANZA_BENEFICIARY_ID]
        .select { |name| value(name).empty? }
      if !missing.empty?
        fail_step("#{missing.join(", ")} not set", "set them in .env")
      elsif value("MANZA_CREATOR_API_KEY") == value("MANZA_AUTHORIZER_API_KEY")
        fail_step("key A and key B are the same key",
          "use two different keys: the API refuses to let the key that created a transfer authorize it")
      else
        pass("key A and key B are set and different")
        return true
      end
      false
    end

    # 2. Key A reaches the API.
    private def creator_reaches_entity : Nil
      entity = creator.entity.get.body
      pass("key A reaches the API (entity #{string(entity, "name").inspect})")
    rescue ex : Manza::Error | Manza::ConnectionError
      fail_step("key A cannot read the entity: #{describe(ex)}", key_fix(ex, "MANZA_CREATOR_API_KEY", "entity:read"))
    end

    # 3. Key B reads the authorizer, which must be active.
    private def enrolled_authorizer : JSON::Any?
      authorizer = authorizer_client.transfer_authorizer.get.body
      if string(authorizer, "status") == "active"
        pass("transfer authorizer is active")
      else
        reason = string(authorizer, "suspension_reason")
        fail_step("transfer authorizer is #{string(authorizer, "status")} (#{reason})",
          reason.try { |key| SUSPENSION_FIXES[key]? } || "see suspension_reason in the transfer authorization docs")
      end
      authorizer
    rescue ex : Manza::Error | Manza::ConnectionError
      if ex.is_a?(Manza::Error) && ex.kind == "not_found"
        fail_step("no transfer authorizer is enrolled", "enrol your webhook endpoint in Settings → Developer → Transfer approval")
      else
        fail_step("key B cannot read the transfer authorizer: #{describe(ex)}",
          key_fix(ex, "MANZA_AUTHORIZER_API_KEY", "transfers:authorize"))
      end
      nil
    end

    private def currency_matches(authorizer : JSON::Any) : Nil
      currency = string(creator.accounts.get(value("MANZA_ACCOUNT_ID")).body, "currency_code")
      enrolled = string(authorizer, "currency_code")
      return pass("account currency #{currency} is the enrolled currency") if currency == enrolled

      fail_step("account currency #{currency} is not the enrolled currency #{enrolled}",
        "pay from a #{enrolled} account (MANZA_ACCOUNT_ID), or enrol #{currency}")
    rescue ex : Manza::Error | Manza::ConnectionError
      fail_step("key A cannot read account #{value("MANZA_ACCOUNT_ID").inspect}: #{describe(ex)}",
        key_fix(ex, "MANZA_CREATOR_API_KEY", "accounts:read", "MANZA_ACCOUNT_ID"))
    end

    private def secret_fresh(authorizer : JSON::Any) : Nil
      expires = string(authorizer, "secret_expires_at").to_s
      days = (Time.parse_iso8601(expires) - @now).total_days.floor.to_i
      return pass("signing secret expires in #{days} days") if days >= SECRET_MIN_DAYS

      fail_step("signing secret #{days.negative? ? "expired" : "expires in #{days} days"} (#{expires})",
        "an approver should rotate the secret in Settings → Developer → Transfer approval; set the new one as " \
        "MANZA_AUTHORIZER_SECRET")
    end

    # 4. The signing secret is set.
    private def secret_set : Nil
      return pass("MANZA_AUTHORIZER_SECRET is set") unless value("MANZA_AUTHORIZER_SECRET").empty?

      fail_step("MANZA_AUTHORIZER_SECRET is not set", "set it to the signing secret shown at enrolment or at the last rotation")
    end

    # 5. The enrolled webhook endpoint is enabled, on a URL that lasts.
    private def endpoint_enabled(authorizer : JSON::Any) : Nil
      endpoint_id = string(authorizer, "webhook_endpoint_id").to_s
      endpoint = creator.webhook_endpoints.get(endpoint_id).body
      url = string(endpoint, "url").to_s
      if string(endpoint, "status") == "active"
        pass("webhook endpoint #{url} is enabled")
      else
        fail_step("webhook endpoint #{url} is #{string(endpoint, "status")}",
          "enable it (webhook_endpoints.enable(#{string(endpoint, "id").inspect})); if the authorizer stays suspended, " \
          "an approver resumes it in the app")
      end
      host = URI.parse(url).host.to_s
      unstable = UNSTABLE_TUNNEL_HOSTS.find { |domain| host == domain || host.ends_with?(".#{domain}") }
      return unless unstable

      warn_step("webhook endpoint is on #{unstable}, whose URL changes when the tunnel restarts",
        "use a reserved domain or a named tunnel, then enrol an endpoint at that URL")
    rescue ex : Manza::Error | Manza::ConnectionError
      if ex.is_a?(Manza::Error) && ex.kind == "not_found"
        fail_step("the enrolled webhook endpoint #{string(authorizer, "webhook_endpoint_id")} was deleted",
          "create an endpoint at a stable URL and enrol it in Settings → Developer → Transfer approval")
      else
        fail_step("key A cannot read the enrolled webhook endpoint: #{describe(ex)}",
          key_fix(ex, "MANZA_CREATOR_API_KEY", "webhook_endpoints:read"))
      end
    end

    # 6a. The test amount fits both limits.
    private def amount_within_limits(authorizer : JSON::Any, amount : BigDecimal) : Nil
      per_transfer = decimal(authorizer, "per_transfer_limit")
      room = decimal(authorizer, "daily_limit") - decimal(authorizer, "daily_authorized_total")
      if amount > per_transfer
        fail_step("#{format_amount(amount)} is over the limit per transfer (#{format_amount(per_transfer)})",
          "send at most #{format_amount(per_transfer)}, or have an approver raise the limit")
      elsif amount > room
        fail_step("#{format_amount(amount)} does not fit the last 24 hours' room (#{format_amount(room)} left)",
          "wait for older authorizations to leave the 24-hour window, or have an approver raise the limit")
      else
        pass("#{format_amount(amount)} is within the limit per transfer and the 24-hour room")
      end
    end

    # 6b. The payee is trusted, or may be trusted on authorize.
    private def payee_trusted : Nil
      beneficiary = creator.beneficiaries.get(value("MANZA_BENEFICIARY_ID")).body
      accounts = beneficiary["external_accounts"]?.try(&.as_a?) || [] of JSON::Any
      account = accounts.find { |candidate| candidate["default"]?.try(&.as_bool?) == true }
      return fail_step("beneficiary has no default bank account", "add one, or set a beneficiary that has one") unless account
      return pass("payee #{string(account, "id")} is trusted") if account["trusted"]?.try(&.as_bool?) == true

      warn_step("payee #{string(account, "id")} is not trusted yet",
        "it qualifies only with \"Approve transfers to new payees\" on in Settings → Developer → Transfer approval " \
        "(not visible through the API), key A bound to an IP allowlist, and the amount within the limit per " \
        "transfer to a new payee, and only if its bank details were never trusted (revoked or edited " \
        "details always go to your approvers); otherwise have an approver trust it")
    rescue ex : Manza::Error | Manza::ConnectionError
      fail_step("key A cannot read beneficiary #{value("MANZA_BENEFICIARY_ID").inspect}: #{describe(ex)}",
        key_fix(ex, "MANZA_CREATOR_API_KEY", "beneficiaries:read", "MANZA_BENEFICIARY_ID"))
    end

    private def creator : Manza::Client
      @creator ||= Manza::Client.new(api_key: value("MANZA_CREATOR_API_KEY"), base_url: base_url)
    end

    private def authorizer_client : Manza::Client
      @authorizer_client ||= Manza::Client.new(api_key: value("MANZA_AUTHORIZER_API_KEY"), base_url: base_url)
    end

    private def base_url : String
      value("MANZA_BASE_URL").empty? ? Manza::Client::DEFAULT_BASE_URL : value("MANZA_BASE_URL")
    end

    private def value(name : String) : String
      @env[name]? || ""
    end

    private def string(body : JSON::Any, key : String) : String?
      body[key]?.try(&.as_s?)
    end

    private def decimal(body : JSON::Any, key : String) : BigDecimal
      BigDecimal.new(string(body, key) || raise "#{key} is missing from the transfer authorizer")
    end

    # `error` is a Manza::Error or a Manza::ConnectionError.
    private def describe(error : Exception) : String
      return "connection failed: #{error.message}" unless error.is_a?(Manza::Error)

      "#{error.kind} #{error.type || error.status}: #{error.message}"
    end

    private def key_fix(error : Exception, key_var : String, scope : String, id_var : String? = nil) : String
      kind = error.is_a?(Manza::Error) ? error.kind : "connection"
      case kind
      when "authentication" then "check #{key_var}: the key is wrong or revoked"
      when "forbidden"      then "give the key the #{scope} scope, or add this machine's address to its IP allowlist"
      when "not_found"      then "check #{id_var || "MANZA_BASE_URL"}"
      else                       "check MANZA_BASE_URL and the network, then rerun"
      end
    end

    # The exact decimal, padded to two places ("10" -> "10.00"), never
    # rounded: the line shows the value that was compared.
    private def format_amount(amount : BigDecimal) : String
      whole, _, fraction = amount.to_s.partition('.')
      "#{whole}.#{fraction.ljust(2, '0')}"
    end

    private def pass(message : String) : Nil
      @out.puts("✓ #{message}")
    end

    private def fail_step(message : String, fix : String) : Nil
      @ok = false
      @out.puts("✗ #{message}: #{fix}")
    end

    private def warn_step(message : String, note : String) : Nil
      @out.puts("! #{message}: #{note}")
    end
  end
end
