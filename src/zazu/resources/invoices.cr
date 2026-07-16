module Zazu
  module Resources
    # Invoices and their lifecycle actions.
    class Invoices < Base
      # GET /api/invoices
      def list(status : String? = nil, customer_id : String? = nil,
               limit : Int32 = MAX_PER_PAGE, cursor : String? = nil) : Page
        list_page("api/invoices", limit, cursor, {
          "status"      => status,
          "customer_id" => customer_id,
        })
      end

      # GET /api/invoices/:id
      def get(id : String) : Response
        http_get(encode_path("api/invoices", id))
      end

      # POST /api/invoices
      def create(**attributes) : Response
        http_post("api/invoices", body: attributes.to_json)
      end

      # PATCH /api/invoices/:id
      def update(id : String, **attributes) : Response
        http_patch(encode_path("api/invoices", id), body: attributes.to_json)
      end

      # POST /api/invoices/:id/send
      def send(id : String) : Response
        http_post(encode_path("api/invoices", id, "send"))
      end

      # POST /api/invoices/:id/mark_as_paid
      def mark_as_paid(id : String) : Response
        http_post(encode_path("api/invoices", id, "mark_as_paid"))
      end

      # POST /api/invoices/:id/cancel
      def cancel(id : String) : Response
        http_post(encode_path("api/invoices", id, "cancel"))
      end

      # POST /api/invoices/:id/credit_note
      def credit_note(id : String) : Response
        http_post(encode_path("api/invoices", id, "credit_note"))
      end

      # DELETE /api/invoices/:id
      def delete(id : String) : Response
        http_delete(encode_path("api/invoices", id))
      end

      # POST /api/invoices/:invoice_id/payment_link
      #
      # `account_id` is the funding account for the link.
      def create_payment_link(invoice_id : String, account_id : String) : Response
        http_post(
          encode_path("api/invoices", invoice_id, "payment_link"),
          body: {account_id: account_id}.to_json
        )
      end
    end
  end
end
