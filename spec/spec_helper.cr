require "spec"
require "../src/manza"
require "./support/env_helpers"
require "./support/fixture_ids"
require "./support/replay_server"
require "./support/stub_server"

# Starts a replay server for the given cassettes, yields a client
# pointed at it, and fails loudly (via `ReplayServer#close`) when any
# request went unmatched.
def with_replay(*names : String, ignore_signature : Bool = false, & : Manza::Client ->)
  server = ReplayServer.new(names.to_a, ignore_signature)
  client = Manza::Client.new(api_key: "test-api-key-for-replay", base_url: server.url)
  begin
    yield client
  ensure
    server.close
  end
end
