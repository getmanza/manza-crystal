module Zazu
  module Resources
    # Individuals or businesses the entity invoices.
    class Customers < Base
      # GET /api/customers
      #
      # `q` matches company name, person name, email.
      def list(q : String? = nil, limit : Int32 = MAX_PER_PAGE, cursor : String? = nil) : Page
        list_page("api/customers", limit, cursor, {"q" => q})
      end

      # GET /api/customers/:id
      def get(id : String) : Response
        http_get(encode_path("api/customers", id))
      end

      # POST /api/customers
      def create(**attributes) : Response
        http_post("api/customers", body: attributes.to_json)
      end

      # PATCH /api/customers/:id
      def update(id : String, **attributes) : Response
        http_patch(encode_path("api/customers", id), body: attributes.to_json)
      end

      # DELETE /api/customers/:id
      def delete(id : String) : Response
        http_delete(encode_path("api/customers", id))
      end
    end
  end
end
