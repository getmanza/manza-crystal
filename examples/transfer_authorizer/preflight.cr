# Checks every setup step before you create a transfer, and says how to fix
# the ones that fail:
#
#   crystal run preflight.cr               # for a 10.00 transfer
#   crystal run preflight.cr -- 250.00
#
# ✓ passed, ✗ failed (exit status 1), ! cannot be checked through the API.
require "../../src/manza"
require "./src/dotenv"
require "./src/preflight"

TransferAuthorizer::DotEnv.overload(File.join(__DIR__, ".env"))
exit(TransferAuthorizer::Preflight.new(amount: ARGV[0]? || "10.00").run ? 0 : 1)
