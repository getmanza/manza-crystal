require "json"

module TransferAuthorizer
  # Your own record of the transfers you created, keyed by the
  # client_reference you generated. A JSON file, so the creator
  # (create_transfer.cr) and the authorizer (server.cr) can run as two
  # processes. Swap it for your database in production.
  #
  # ```json
  # {"po_8812": {"payment_id": "...", "amount": "2500.0", "currency_code": "MAD",
  #              "account_id": "...", "payee": "ext:..."}}
  # ```
  class Ledger
    alias Entry = Hash(String, String)

    def initialize(@path : String)
    end

    def record(client_reference : String, payment_id : String, amount : String, currency_code : String,
               account_id : String, payee : String) : Entry
      entry = {"payment_id" => payment_id, "amount" => amount, "currency_code" => currency_code,
               "account_id" => account_id, "payee" => payee}

      # Serialize writers on a separate lock file, write the new ledger to a
      # temporary file and rename it over the old one: a reader sees the old
      # or the new ledger, never a half-written one, and a crash mid-write
      # leaves the old ledger intact.
      File.open("#{@path}.lock", "a", perm: 0o600) do |lock|
        lock.flock_exclusive do
          entries = read_entries
          entries[client_reference] = entry
          tmp = "#{@path}.#{Process.pid}.tmp"
          File.write(tmp, entries.to_pretty_json, perm: 0o600)
          File.rename(tmp, @path)
        end
      end
      entry
    end

    # The entry for `client_reference`, or nil.
    def find(client_reference : String) : Entry?
      read_entries[client_reference]?
    end

    private def read_entries : Hash(String, Entry)
      return Hash(String, Entry).new unless File.exists?(@path)

      json = File.read(@path)
      json.blank? ? Hash(String, Entry).new : Hash(String, Entry).from_json(json)
    end
  end
end
