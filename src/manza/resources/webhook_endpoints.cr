module Manza
  module Resources
    # Webhook endpoint management.
    class WebhookEndpoints < Base
      # GET /api/webhook_endpoints
      def list(limit : Int32 = MAX_PER_PAGE, cursor : String? = nil) : Page
        list_page("api/webhook_endpoints", limit, cursor)
      end

      # GET /api/webhook_endpoints/:id
      def get(id : String) : Response
        http_get(encode_path("api/webhook_endpoints", id))
      end

      # POST /api/webhook_endpoints
      def create(**attributes) : Response
        http_post("api/webhook_endpoints", body: attributes.to_json)
      end

      # PATCH /api/webhook_endpoints/:id
      def update(id : String, **attributes) : Response
        http_patch(encode_path("api/webhook_endpoints", id), body: attributes.to_json)
      end

      # DELETE /api/webhook_endpoints/:id
      def delete(id : String) : Response
        http_delete(encode_path("api/webhook_endpoints", id))
      end

      # POST /api/webhook_endpoints/:id/test
      def test(id : String) : Response
        http_post(encode_path("api/webhook_endpoints", id, "test"))
      end

      # POST /api/webhook_endpoints/:id/regenerate_secret
      def regenerate_secret(id : String) : Response
        http_post(encode_path("api/webhook_endpoints", id, "regenerate_secret"))
      end

      # POST /api/webhook_endpoints/:id/enable
      def enable(id : String) : Response
        http_post(encode_path("api/webhook_endpoints", id, "enable"))
      end

      # POST /api/webhook_endpoints/:id/disable
      def disable(id : String) : Response
        http_post(encode_path("api/webhook_endpoints", id, "disable"))
      end
    end
  end
end
