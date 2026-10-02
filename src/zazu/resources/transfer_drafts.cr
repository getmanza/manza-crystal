module Zazu
  module Resources
    # API-initiated transfers. Creating a draft never executes a
    # transfer by itself. A draft inside the entity's machine-
    # authorization envelope (trusted payee, within limits) is sent to
    # the enrolled transfer authorizer as a `payment.authorization_requested`
    # webhook; answer it with `#authorize` or `#decline`, using an API
    # key other than the one that created the draft. Every other draft
    # goes to the in-app approval flow, where a manager or legal
    # representative approves it. Poll `#get` (status: requested →
    # processing → completed / failed) or subscribe to the
    # `transfer.executed` webhook to follow execution.
    class TransferDrafts < Base
      # POST /api/transfer_drafts
      #
      # Required: account_id, amount, and exactly one of beneficiary_id
      # (external transfer) or destination_account_id (own-account move).
      # Optional: external_account_id, currency_code, payment_reference,
      # internal_notes, client_reference (unique per entity, at most 128
      # characters; a duplicate raises `Zazu::ConflictError` whose
      # `payment_id` names the existing draft).
      def create(**attributes) : Response
        http_post("api/transfer_drafts", body: attributes.to_json)
      end

      # GET /api/transfer_drafts/:id
      def get(id : String) : Response
        http_get(encode_path("api/transfer_drafts", id))
      end

      # POST /api/transfer_drafts/:id/authorize
      #
      # Executes the draft. `authorization_id` comes from the
      # `payment.authorization_requested` webhook; build `signature` with
      # `Zazu::TransferAuthorization`. Requires the `transfers:authorize`
      # scope on a key other than the draft's creator (otherwise 403
      # `same_key_forbidden`). A blank signature raises
      # `Zazu::ArgumentError` locally: the API counts it as a failed
      # attempt, and five fail the challenge.
      def authorize(id : String, authorization_id : String, signature : String) : Response
        raise Zazu::ArgumentError.new("signature cannot be blank") if signature.blank?

        body = {authorization_id: authorization_id, signature: signature}
        http_post(encode_path("api/transfer_drafts", id, "authorize"), body: body.to_json)
      end

      # POST /api/transfer_drafts/:id/decline
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
        http_post(encode_path("api/transfer_drafts", id, "decline"), body: body)
      end
    end
  end
end
