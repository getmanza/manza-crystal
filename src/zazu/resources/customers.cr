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
      #
      # Common keys: customer_type ("individual" | "business"),
      # person_name, company_name, email, phone, registration_number,
      # vat_number, billing_address (object with street/city/postal_code/
      # country/country_code). Morocco only: tax_id, ice_number — these
      # keys are absent from responses in other markets.
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
