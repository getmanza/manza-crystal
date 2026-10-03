module Manza
  module Resources
    # Requests to trust payees for machine-authorized transfers. The API
    # key can only ask: a member holding payment-authorize permission
    # approves the request in the Manza app. Status: pending → approved /
    # declined / cancelled. There is no list, update, or delete.
    class PayeeTrustRequests < Base
      # POST /api/payee_trust_requests
      #
      # `external_account_ids` holds at most 100 bank accounts.
      def create(external_account_ids : Array(String)) : Response
        http_post("api/payee_trust_requests", body: {external_account_ids: external_account_ids}.to_json)
      end

      # GET /api/payee_trust_requests/:id
      def get(id : String) : Response
        http_get(encode_path("api/payee_trust_requests", id))
      end
    end
  end
end
