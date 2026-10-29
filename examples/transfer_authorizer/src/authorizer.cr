require "http/server"
require "../../../src/manza"
require "./ledger"

module TransferAuthorizer
  # An `HTTP::Handler` that answers `payment.authorization_requested`
  # webhooks with key B (the authorizer key):
  #
  # 1. Verify the delivery (401 when the signature or timestamp is bad).
  # 2. Find the draft in your own ledger by its client_reference.
  # 3. Missing or different from what you created → decline with a reason.
  # 4. A payee not trusted yet (`payee_trusted: false`, only with "Approve
  #    transfers to new payees" on) is trusted by the authorize, unless
  #    `allow_new_payees: false` (ALLOW_NEW_PAYEES=false) declines it.
  # 5. Otherwise sign the challenge from the ledger and authorize it.
  #
  # It answers 200 first and does steps 2-5 on the executor (a new fiber
  # by default): the delivery has a timeout, and a retried webhook is safe
  # because authorize replays idempotently.
  class App
    include HTTP::Handler

    EVENT = "payment.authorization_requested"

    # Ledger field → webhook `data.payment` field. All must match.
    CHECKED_FIELDS = {
      "payment_id"    => "id",
      "amount"        => "amount",
      "currency_code" => "currency_code",
      "account_id"    => "account_id",
      "payee"         => "payee",
    }

    # A 409 of this type means a bank-detail edit, trust or revocation on
    # the same payee was in flight: retry.
    BUSY            = "authorization_busy"
    ATTEMPTS        = 3
    MAX_RETRY_AFTER = 30.seconds # a challenge expires, so never park the fiber for long

    alias Executor = Proc(Proc(Nil), Nil)

    # `ledger_wait`: how long to wait for the ledger entry. The webhook can
    # arrive before create_transfer.cr has written the entry from the
    # create response. `retry_delay`: base delay between attempts.
    # `allow_new_payees: false` declines transfers to payees not trusted yet.
    def initialize(@client : Manza::Client, @secret : String, @ledger : Ledger,
                   @executor : Executor = ->(job : Proc(Nil)) { spawn { job.call }; nil },
                   @log : IO = STDOUT, @ledger_wait : Time::Span = 10.seconds,
                   @retry_delay : Time::Span = 2.seconds, @allow_new_payees : Bool = true)
    end

    def call(context : HTTP::Server::Context) : Nil
      body = context.request.body.try(&.gets_to_end) || ""
      event = verify(body, context.request.headers)
      return respond(context, 401) unless event
      return ignore(context, event) unless event["event"]?.try(&.as_s?) == EVENT

      data = event["data"]? || JSON::Any.new(nil)
      @executor.call(-> { answer(data) })
      respond(context, 200)
    end

    private def verify(body : String, headers : HTTP::Headers) : JSON::Any?
      event = Manza::Webhook.construct_event(body, headers, @secret)
      info("received #{event["event"]?} (#{event["event_id"]?}), signature verified")
      event
    rescue ex : Manza::ArgumentError
      warn("rejected a delivery: #{ex.message}")
      nil
    end

    private def ignore(context : HTTP::Server::Context, event : JSON::Any) : Nil
      info("ignoring #{event["event"]?}: this app only answers #{EVENT}")
      respond(context, 200)
    end

    private def answer(data : JSON::Any) : Nil
      payment = data["payment"]
      authorization = data["authorization"]
      payment_id = payment["id"].as_s
      authorization_id = authorization["id"].as_s
      client_reference = payment["client_reference"]?.try(&.as_s?)
      entry = wait_for_entry(client_reference)

      mismatch = entry ? mismatch_reason(entry, payment) : "client_reference #{client_reference.inspect} is not in the ledger"
      return decline(payment_id, authorization_id, mismatch) if mismatch || entry.nil?

      # Anything but true counts as new, so a webhook without the field is
      # declined under ALLOW_NEW_PAYEES=false rather than trusted blindly.
      unless payment["payee_trusted"]?.try(&.as_bool?) == true
        unless @allow_new_payees
          return decline(payment_id, authorization_id,
            "new payee #{payment["payee"]?}: ALLOW_NEW_PAYEES=false declines payees not trusted yet")
        end

        info("new payee #{payment["payee"]?}, will be trusted on authorize")
      end

      info("ledger match for #{client_reference}: #{payment["amount"]?} #{payment["currency_code"]?} to #{payment["payee"]?}")
      authorize(entry, authorization, client_reference, data["signature_input"]?.try(&.as_s?))
    rescue ex : Manza::Error
      error("API error #{ex.class.name} #{ex.kind}: #{ex.message} (type #{ex.type.inspect}, request_id #{ex.request_id.inspect})")
    rescue ex : Manza::ConnectionError
      error("API error #{ex.class.name}: #{ex.message}")
    rescue ex
      error("could not answer the challenge: #{ex.class}: #{ex.message}")
    end

    private def wait_for_entry(client_reference : String?) : Ledger::Entry?
      return nil unless client_reference

      deadline = Time.utc + @ledger_wait
      loop do
        entry = @ledger.find(client_reference)
        return entry if entry || Time.utc >= deadline

        sleep 0.5.seconds
      end
    end

    private def mismatch_reason(entry : Ledger::Entry, payment : JSON::Any) : String?
      CHECKED_FIELDS.each do |ledger_field, webhook_field|
        webhook_value = payment[webhook_field]?.try(&.as_s?)
        next if entry[ledger_field]? == webhook_value

        return "#{ledger_field} differs from the ledger (ledger #{entry[ledger_field]?.inspect}, webhook #{webhook_value.inspect})"
      end
      nil
    end

    # Sign from the ledger, never from the webhook: `signature_input` in the
    # webhook is only there to compare against.
    private def authorize(entry : Ledger::Entry, authorization : JSON::Any, client_reference : String?,
                          webhook_input : String?) : Nil
      input = Manza::TransferAuthorization.signature_input(
        entry["payment_id"], authorization["nonce"].as_s, entry["amount"], entry["currency_code"],
        entry["account_id"], entry["payee"], client_reference
      )
      # A signature over a different input is sure to fail, and failed
      # attempts count toward suspending the authorizer. Leave the challenge
      # unanswered instead: it expires and goes to your approvers.
      unless input == webhook_input
        warn("signature input differs from the webhook's: ledger #{input.inspect}, webhook #{webhook_input.inspect}; " \
             "not answering, the challenge goes to your approvers when it expires")
        return
      end

      signature = Manza::TransferAuthorization.sign(@secret, input)
      info("signed the challenge for payment #{entry["payment_id"]}")

      response = with_retries do
        @client.payments.authorize(entry["payment_id"], authorization["id"].as_s, signature)
      end
      info("authorized payment #{entry["payment_id"]} (status #{response.body["status"]?.try(&.as_s?).inspect})")
    end

    private def decline(payment_id : String, authorization_id : String, reason : String?) : Nil
      with_retries { @client.payments.decline(payment_id, authorization_id, reason) }
      warn("declined payment #{payment_id}: #{reason}")
    end

    # Retries what is worth another try: the API did not answer, answered
    # 5xx, asked us to slow down, or was busy with the same payee (409
    # `authorization_busy`). Authorize and decline replay idempotently, so
    # a retry is safe.
    private def with_retries(& : -> Manza::Response) : Manza::Response
      attempt = 1
      loop do
        begin
          return yield
        rescue ex : Manza::Error
          raise ex if attempt >= ATTEMPTS || !transient?(ex)

          pause(ex.class.name, ex.request_id, retry_delay(ex, attempt))
        rescue ex : Manza::ConnectionError
          raise ex if attempt >= ATTEMPTS

          pause(ex.class.name, nil, @retry_delay * attempt)
        end
        attempt += 1
      end
    end

    private def transient?(ex : Manza::Error) : Bool
      ex.kind.in?("server", "rate_limit") || (ex.kind == "conflict" && ex.type == BUSY)
    end

    private def retry_delay(ex : Manza::Error, attempt : Int32) : Time::Span
      if ex.kind == "rate_limit" && (seconds = ex.retry_after)
        return {seconds.seconds, MAX_RETRY_AFTER}.min
      end

      @retry_delay * attempt
    end

    private def pause(error_name : String, request_id : String?, delay : Time::Span) : Nil
      warn("#{error_name} (request_id #{request_id.inspect}), retrying in #{delay.total_seconds}s")
      sleep delay
    end

    private def respond(context : HTTP::Server::Context, status : Int32) : Nil
      context.response.status_code = status
      context.response.content_type = "text/plain"
      context.response.print(status == 200 ? "ok" : "unauthorized")
    end

    private def info(message : String) : Nil
      log("INFO", message)
    end

    private def warn(message : String) : Nil
      log("WARN", message)
    end

    private def error(message : String) : Nil
      log("ERROR", message)
    end

    private def log(level : String, message : String) : Nil
      @log.puts("#{Time.local.to_s("%Y-%m-%dT%H:%M:%S")} #{level} #{message}")
    end
  end
end
