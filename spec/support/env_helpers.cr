CLIENT_ENV_NAMES = %w(API_KEY BASE_URL API_VERSION)

# Runs the block with every MANZA_*/ZAZU_* client variable cleared and a
# fresh warning registry writing to a memory buffer, then restores both.
def with_clean_env(& : IO::Memory ->)
  saved = {} of String => String?
  CLIENT_ENV_NAMES.each do |name|
    {"MANZA_", "ZAZU_"}.each do |prefix|
      saved[prefix + name] = ENV[prefix + name]?
      ENV.delete(prefix + name)
    end
  end
  io = IO::Memory.new
  Manza::Env.warn_io = io
  Manza::Env.reset_warnings
  begin
    yield io
  ensure
    saved.each { |key, value| value ? (ENV[key] = value) : ENV.delete(key) }
    Manza::Env.warn_io = STDERR
    Manza::Env.reset_warnings
  end
end
