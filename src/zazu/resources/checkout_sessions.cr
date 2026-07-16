module Zazu
  module Resources
    # One-off hosted checkout sessions. No list, update, or delete;
    # sessions are created and inspected by id.
    class CheckoutSessions < Base
      # POST /api/checkout_sessions
      #
      # Required attributes: account_id, amount, success_url.
      def create(**attributes) : Response
        http_post("api/checkout_sessions", body: attributes.to_json)
      end

      # GET /api/checkout_sessions/:id
      def get(id : String) : Response
        http_get(encode_path("api/checkout_sessions", id))
      end
    end
  end
end
