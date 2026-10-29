# The authorizer process (key B). Point your tunnel at PORT (default 4599):
#
#   crystal run server.cr
require "../../src/manza"
require "./src/dotenv"
require "./src/authorizer"

STDOUT.sync = true
env_file = File.join(__DIR__, ".env")
TransferAuthorizer::DotEnv.overload(env_file)

missing = %w[MANZA_AUTHORIZER_API_KEY MANZA_AUTHORIZER_SECRET].select { |name| ENV.fetch(name, "").empty? }
abort "Set #{missing.join(" and ")} in #{env_file}" unless missing.empty?

app = TransferAuthorizer::App.new(
  client: Manza::Client.new(api_key: ENV["MANZA_AUTHORIZER_API_KEY"]),
  secret: ENV["MANZA_AUTHORIZER_SECRET"],
  ledger: TransferAuthorizer::Ledger.new(File.join(__DIR__, "ledger.json")),
  allow_new_payees: !%w[false 0 no].includes?(ENV.fetch("ALLOW_NEW_PAYEES", "true").strip.downcase)
)

server = HTTP::Server.new([app] of HTTP::Handler)
address = server.bind_tcp("127.0.0.1", ENV.fetch("PORT", "4599").to_i)
puts "listening on http://#{address}"
server.listen
