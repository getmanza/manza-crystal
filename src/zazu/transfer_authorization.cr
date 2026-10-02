require "openssl/hmac"

module Zazu
  # Signs a machine-authorization challenge for an API-created transfer
  # draft. Pure functions — no HTTP.
  #
  # The `payment.authorization_requested` webhook delivers the
  # authorization id and a one-time nonce. Build the signature input
  # from your *own* record of the transfer (not the webhook's
  # `signature_input`, which is there only to compare against), sign it
  # with the authorizer endpoint's signing secret, and pass the result to
  # `Resources::TransferDrafts#authorize`:
  #
  # ```
  # input = Zazu::TransferAuthorization.signature_input(
  #   draft["id"].as_s, nonce, draft["amount"].as_s, draft["currency_code"].as_s,
  #   draft["account_id"].as_s,
  #   Zazu::TransferAuthorization.payee_for(external_account_id: draft["external_account_id"].as_s),
  #   draft["client_reference"].as_s?
  # )
  # signature = Zazu::TransferAuthorization.sign(signing_secret, input)
  # authorizer.transfer_drafts.authorize(draft["id"].as_s, authorization_id, signature)
  # ```
  module TransferAuthorization
    SIGNATURE_VERSION = "manza.transfer-authorization.v1"

    # `amount` must be the API's decimal string verbatim (e.g. "2500.0"),
    # which is why it is a `String` and not a number. `client_reference`
    # is empty when the transfer has none.
    def self.signature_input(payment_id : String, nonce : String, amount : String,
                             currency_code : String, account_id : String, payee : String,
                             client_reference : String? = nil) : String
      [SIGNATURE_VERSION, payment_id, nonce, amount, currency_code, account_id, payee,
       client_reference.to_s].join('|')
    end

    # Lowercase hex HMAC-SHA256 of the signature input under the
    # authorizer endpoint's signing secret.
    def self.sign(secret : String, signature_input : String) : String
      OpenSSL::HMAC.hexdigest(:sha256, secret, signature_input)
    end

    # The payee token: `ext:<id>` for a beneficiary's bank account,
    # `own:<id>` for one of the entity's own accounts. Pass exactly one.
    def self.payee_for(external_account_id : String? = nil, destination_account_id : String? = nil) : String
      if external_account_id && destination_account_id.nil?
        "ext:#{external_account_id}"
      elsif destination_account_id && external_account_id.nil?
        "own:#{destination_account_id}"
      else
        raise Zazu::ArgumentError.new("pass exactly one of external_account_id or destination_account_id")
      end
    end
  end
end
