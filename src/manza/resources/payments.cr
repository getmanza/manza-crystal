module Manza
  module Resources
    # API-initiated transfers, called payments (formerly transfer drafts;
    # `/api/transfer_drafts` stays a permanent server-side alias). Creating
    # a draft never executes a transfer by itself. A draft inside the entity's machine-
    # authorization envelope (trusted payee, within limits) is sent to
    # the enrolled transfer authorizer as a `payment.authorization_requested`
    # webhook; answer it with `#authorize` or `#decline`, using an API
    # key other than the one that created the draft. Every other draft
    # goes to the in-app approval flow, where a manager or legal
    # representative approves it. Poll `#get` (status: requested →
    # processing → completed / failed) or subscribe to the
    # `transfer.executed` webhook to follow execution.
    #
    # A draft's `authorization` says which way it went: `pending` (a
    # challenge was sent), `authorized`, `declined` (the draft is deleted),
    # or one of two outcomes that send the draft to the in-app approvers,
    # each with a `refusal_reason`:
    #
    # - `refused`: it did not qualify, at create time (no webhook is sent)
    #   or again when the challenge was answered: `untrusted_payee`,
    #   `unrestricted_api_key`, `over_new_payee_limit`,
    #   `over_transfer_limit`, `over_daily_limit`, `currency_mismatch`,
    #   `suspended` or `secret_expired`.
    # - `expired` / `superseded` / `failed`: a challenge was sent and closed
    #   without an authorize: `expired` (no answer within the hour),
    #   `stale` (the draft, its payee's bank details or the endpoint changed
    #   while it was open) or `signature_failed` (five invalid signatures).
    #
    # `authorization` is null when no authorizer was enrolled.
    #
    # With "Approve transfers to new payees" on (enrolment, in the app),
    # a draft to bank details the entity never trusted is challenged too,
    # up to the new-payee limit, when the creating key has an IP
    # allowlist; authorizing it also trusts the payee.
    class Payments < Base
      # POST /api/payments
      #
      # Required: account_id, amount, and exactly one of beneficiary_id
      # (external transfer) or destination_account_id (own-account move).
      # Optional: external_account_id, currency_code, payment_reference,
      # internal_notes, client_reference (unique per entity, at most 128
      # characters; a duplicate raises `Manza::ConflictError` whose
      # `payment_id` names the existing draft).
      def create(**attributes) : Response
        http_post("api/payments", body: attributes.to_json)
      end

      # GET /api/payments/:id
      def get(id : String) : Response
        http_get(encode_path("api/payments", id))
      end

      # POST /api/payments/:id/authorize
      #
      # Executes the draft. `authorization_id` comes from the
      # `payment.authorization_requested` webhook; build `signature` with
      # `Manza::TransferAuthorization`. Requires the `transfers:authorize`
      # scope on a key other than the draft's creator (otherwise 403
      # `same_key_forbidden`), bound to an IP allowlist (otherwise 403
      # `unrestricted_api_key`). A 409 `Manza::ConflictError` with `type`
      # `authorization_busy` means a bank-detail edit, trust or trust
      # revocation on the payee was in flight: retry. A blank signature
      # raises `Manza::ArgumentError` locally and is never sent, because the
      # API would count it as a failed attempt (five fail the challenge).
      def authorize(id : String, authorization_id : String, signature : String) : Response
        raise Manza::ArgumentError.new("signature cannot be blank") if signature.blank?

        body = {authorization_id: authorization_id, signature: signature}
        http_post(encode_path("api/payments", id, "authorize"), body: body.to_json)
      end

      # POST /api/payments/:id/decline
      #
      # Declines the challenge and deletes the draft. Returns the
      # authorization (`status: "declined"`). `reason` is omitted from the
      # request when absent.
      def decline(id : String, authorization_id : String, reason : String? = nil) : Response
        body = JSON.build do |json|
          json.object do
            json.field "authorization_id", authorization_id
            json.field "reason", reason if reason
          end
        end
        http_post(encode_path("api/payments", id, "decline"), body: body)
      end
    end
  end
end
