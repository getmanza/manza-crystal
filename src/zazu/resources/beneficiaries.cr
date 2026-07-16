module Zazu
  module Resources
    # Read-only directory of saved transfer recipients. Each
    # beneficiary embeds its bank accounts; the one flagged `default`
    # is used when a transfer names only the beneficiary_id.
    # Beneficiaries are created and managed in the Zazu dashboard.
    class Beneficiaries < Base
      # GET /api/beneficiaries
      def list(limit : Int32 = MAX_PER_PAGE, cursor : String? = nil) : Page
        list_page("api/beneficiaries", limit, cursor)
      end

      # GET /api/beneficiaries/:id
      def get(id : String) : Response
        http_get(encode_path("api/beneficiaries", id))
      end
    end
  end
end
