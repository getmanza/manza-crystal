module Zazu
  module Resources
    # Accounts and their transactions.
    class Accounts < Base
      # GET /api/accounts
      def list(status : String? = nil, currency_code : String? = nil,
               limit : Int32 = MAX_PER_PAGE, cursor : String? = nil) : Page
        list_page("api/accounts", limit, cursor, {
          "status"        => status,
          "currency_code" => currency_code,
        })
      end

      # GET /api/accounts/:id
      def get(id : String) : Response
        http_get(encode_path("api/accounts", id))
      end

      # GET /api/accounts/:account_id/transactions
      #
      # `posted_after` / `posted_before` are ISO-8601 timestamps; `Time`
      # values are serialized for you.
      def list_transactions(account_id : String, operation : String? = nil,
                            posted_after : String | Time | Nil = nil,
                            posted_before : String | Time | Nil = nil,
                            limit : Int32 = MAX_PER_PAGE, cursor : String? = nil) : Page
        list_page(encode_path("api/accounts", account_id, "transactions"), limit, cursor, {
          "operation"     => operation,
          "posted_after"  => serialize_time(posted_after),
          "posted_before" => serialize_time(posted_before),
        })
      end

      # GET /api/accounts/:account_id/transactions/:id
      def get_transaction(account_id : String, transaction_id : String) : Response
        http_get(encode_path("api/accounts", account_id, "transactions", transaction_id))
      end

      private def serialize_time(value : String | Time | Nil) : String?
        case value
        in String then value
        in Time   then value.to_rfc3339
        in Nil    then nil
        end
      end
    end
  end
end
