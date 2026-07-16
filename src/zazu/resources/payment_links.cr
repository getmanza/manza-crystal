module Zazu
  module Resources
    # Standalone payment links (not attached to an invoice).
    class PaymentLinks < Base
      # GET /api/payment_links
      def list(status : String? = nil, link_type : String? = nil,
               limit : Int32 = MAX_PER_PAGE, cursor : String? = nil) : Page
        list_page("api/payment_links", limit, cursor, {
          "status"    => status,
          "link_type" => link_type,
        })
      end

      # GET /api/payment_links/:id
      def get(id : String) : Response
        http_get(encode_path("api/payment_links", id))
      end

      # POST /api/payment_links
      def create(**attributes) : Response
        http_post("api/payment_links", body: attributes.to_json)
      end

      # POST /api/payment_links/:id/cancel
      def cancel(id : String) : Response
        http_post(encode_path("api/payment_links", id, "cancel"))
      end
    end
  end
end
