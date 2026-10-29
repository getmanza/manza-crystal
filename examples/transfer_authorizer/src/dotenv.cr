module TransferAuthorizer
  # Loads `KEY=VALUE` lines from a `.env` file into `ENV`, overriding what
  # is already set (dotenv's `overload`), so a stale exported variable
  # never masks the file. Enough for this example: blank lines and `#`
  # comments are skipped, and one pair of surrounding quotes is stripped.
  # Use a dotenv shard if you need more.
  module DotEnv
    def self.overload(path : String) : Nil
      return unless File.exists?(path)

      File.each_line(path) do |line|
        line = line.strip
        next if line.empty? || line.starts_with?('#')

        key, separator, value = line.partition('=')
        next if separator.empty?

        value = value.strip
        if value.size >= 2 && value[0] == value[-1] && value[0].in?('"', '\'')
          value = value[1...-1]
        end
        ENV[key.strip] = value
      end
    end
  end
end
