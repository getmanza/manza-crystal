module Manza
  # Reads client configuration from the environment. `MANZA_<NAME>` wins;
  # the pre-1.0 `ZAZU_<NAME>` is still honoured for all of 1.x and warns
  # once per variable per process.
  module Env
    @@warned = Set(String).new
    @@mutex = Mutex.new
    @@warn_io : IO = STDERR

    # :nodoc:
    def self.warn_io=(io : IO)
      @@warn_io = io
    end

    # :nodoc:
    def self.reset_warnings
      @@mutex.synchronize { @@warned.clear }
    end

    def self.fetch(name : String) : String?
      if value = ENV["MANZA_#{name}"]?
        return value
      end

      legacy = "ZAZU_#{name}"
      if value = ENV[legacy]?
        warn_once(legacy, "MANZA_#{name}")
        return value
      end
      nil
    end

    private def self.warn_once(legacy : String, current : String)
      first = @@mutex.synchronize { @@warned.add?(legacy) }
      @@warn_io.puts "manza: #{legacy} is deprecated, use #{current} (support for #{legacy} ends in 2.0)" if first
    end
  end
end
