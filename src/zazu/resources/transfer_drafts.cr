module Zazu
  module Resources
    # API-initiated transfers. Creating a draft routes it into the
    # workspace's in-app approval flow — the API never executes a
    # transfer itself. A manager or legal representative approves in
    # the Zazu app; poll `#get` (status: requested → processing →
    # completed / failed) or subscribe to the `transfer.executed`
    # webhook to follow execution.
    class TransferDrafts < Base
      # POST /api/transfer_drafts
      #
      # Required: account_id, amount, and exactly one of beneficiary_id
      # (external transfer) or destination_account_id (own-account move).
      # Optional: external_account_id, currency_code, payment_reference,
      # internal_notes.
      def create(**attributes) : Response
        http_post("api/transfer_drafts", body: attributes.to_json)
      end

      # GET /api/transfer_drafts/:id
      def get(id : String) : Response
        http_get(encode_path("api/transfer_drafts", id))
      end
    end
  end
end
