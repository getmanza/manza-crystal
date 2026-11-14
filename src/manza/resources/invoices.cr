module Manza
  module Resources
    # Invoices and their lifecycle actions.
    #
    # `status`: draft, pending_approval, declined, approved, sent, paid,
    # overdue or cancelled.
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
      #
      # Required: customer_id, account_id (the entity's account the invoice
      # is paid into, from `Accounts#list`; without one the API answers 422
      # `state_error`, and an account that is not the entity's 422 with
      # `param` "account_id"), issue_date, due_date and items. Optional:
      # currency_code, reference, notes, payment_terms, send_to_email,
      # discounts, delivery_date (MA only) and generate_payment_link.
      #
      # `generate_payment_link: true` asks for a card payment link, made
      # from the invoice's account when the invoice is approved; it needs
      # the `payment_links:write` scope and is taken only while payment
      # links are enabled for the entity. A boolean, nil (no link) or the
      # strings "true", "false", "1" and "0" are taken; any other value
      # raises `Manza::Error` (`kind` "validation", 400) and nothing is
      # created. It replaces the removed `create_payment_link`.
      #
      # The response carries `generate_payment_link`, the embedded
      # `account` (`id`, `name`, `currency_code`, and `rib` in Morocco or
      # `account_number` in South Africa) and `payment_link` once one
      # exists. A plan that caps invoices raises
      # `Manza::PlanLimitReachedError`.
      def create(**attributes) : Response
        http_post("api/invoices", body: attributes.to_json)
      end

      # PATCH /api/invoices/:id
      #
      # Takes the create fields, account_id and generate_payment_link
      # included (the same scope and entity rule apply), on an invoice
      # that is still editable.
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
      #
      # Only a `draft`, `pending_approval` or `declined` invoice that has
      # no number yet; any other raises `Manza::Error` (`kind`
      # "validation", `type` "state_error").
      def delete(id : String) : Response
        http_delete(encode_path("api/invoices", id))
      end
    end
  end
end
