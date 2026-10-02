module Manza
  module Resources
    # One-off hosted checkout sessions. No list, update, or delete;
    # sessions are created and inspected by id. Status is one of `open`,
    # `processing`, `clearing`, `complete`, `expired`. Responses carry
    # `settled_at` and the paying `transaction`.
    class CheckoutSessions < Base
      # POST /api/checkout_sessions
      #
      # Required attributes: account_id, amount, success_url.
      # Optional: metadata, customer_email, customer_name, cancel_url,
      # description, expires_at, collect_billing_address, billing_address.
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
