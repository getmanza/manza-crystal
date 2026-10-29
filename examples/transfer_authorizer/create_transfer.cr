# The creator process (key A). Creates a transfer draft, writes it to the
# ledger from the API's response, and says where the API routed it.
#
#   crystal run create_transfer.cr             # 10.00
#   crystal run create_transfer.cr -- 250.00
require "random/secure"
require "../../src/manza"
require "./src/dotenv"
require "./src/ledger"
require "./src/routing"

TransferAuthorizer::DotEnv.overload(File.join(__DIR__, ".env"))

amount = ARGV[0]? || "10.00"
client_reference = "example-#{Random::Secure.hex(6)}"
ledger = TransferAuthorizer::Ledger.new(File.join(__DIR__, "ledger.json"))
creator = Manza::Client.new(api_key: ENV["MANZA_CREATOR_API_KEY"])

draft = begin
  creator.payments.create(
    account_id: ENV["MANZA_ACCOUNT_ID"],
    beneficiary_id: ENV["MANZA_BENEFICIARY_ID"],
    amount: amount,
    payment_reference: "Transfer authorizer example",
    client_reference: client_reference
  ).body
rescue ex : Manza::Error
  # A timeout may still have created the draft: look for this client_reference
  # in the app before rerunning, or the rerun creates a second transfer.
  abort "create failed for client_reference #{client_reference}: #{ex.class.name} #{ex.kind}: #{ex.message} " \
        "(type #{ex.type.inspect}, request_id #{ex.request_id.inspect})"
rescue ex : Manza::ConnectionError
  abort "create failed for client_reference #{client_reference}: #{ex.class.name}: #{ex.message} " \
        "(the draft may exist anyway: look for this client_reference before rerunning)"
end

payment_id = draft["id"].as_s
destination = draft["destination_account_id"]?.try(&.as_s?)
payee = begin
  Manza::TransferAuthorization.payee_for(
    external_account_id: destination ? nil : draft["external_account_id"]?.try(&.as_s?),
    destination_account_id: destination
  )
rescue Manza::ArgumentError
  abort "payment #{payment_id} names neither an external_account_id nor a destination_account_id, so it was not " \
        "written to the ledger: if it reaches the authorizer, the authorizer declines it"
end

begin
  ledger.record(
    client_reference,
    payment_id: payment_id, amount: draft["amount"].as_s, currency_code: draft["currency_code"].as_s,
    account_id: draft["account_id"].as_s, payee: payee
  )
rescue ex
  abort "payment #{payment_id} (client_reference #{client_reference}) was created but not written to the ledger " \
        "(#{ex.class}: #{ex.message}): if it reaches the authorizer, the authorizer declines it"
end
puts "created payment #{payment_id}: #{draft["amount"]} #{draft["currency_code"]} to #{payee} (client_reference #{client_reference})"

puts TransferAuthorizer::Routing.describe(draft["authorization"]?)
