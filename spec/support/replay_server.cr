require "base64"
require "http/server"
require "json"
require "uri"
require "yaml"

# Reads VCR YAML cassettes (recorded by zazu-ruby) and serves them from
# a stdlib HTTP::Server bound to an ephemeral 127.0.0.1 port, so
# identical interactions replay against this SDK. The contract is
# enforced cross-language: every SDK that consumes the cassette tarball
# must replay the exact request shape.
#
# Matching is method + path+query (host ignored) + semantic JSON body
# (both sides are parsed and compared — key order never matters).
class ReplayServer
  CASSETTE_DIR = File.join(__DIR__, "..", "fixtures", "cassettes")

  record Interaction,
    method : String,
    uri : String,
    request_body : String,
    status : Int32,
    response_body : String

  getter port : Int32

  @interactions : Array(Interaction)
  @server : HTTP::Server
  @unmatched = [] of String

  def initialize(names : Array(String))
    @interactions = names.flat_map { |name| self.class.load_cassette(name) }
    @server = HTTP::Server.new { |context| handle(context) }
    address = @server.bind_tcp("127.0.0.1", 0)
    @port = address.port
    server = @server
    spawn { server.listen }
  end

  def url : String
    "http://127.0.0.1:#{@port}"
  end

  # Shuts the server down; raises if any request went unmatched so the
  # failure surfaces even when the client swallowed the 501.
  def close
    @server.close
    unless @unmatched.empty?
      raise "no cassette interaction matches: #{@unmatched.join("; ")}"
    end
  end

  # Loads the named cassette (e.g. "payment_links/list"). Parses the
  # raw YAML node tree because Ruby's Psych writes non-UTF-8 bodies as
  # base64 with the PRIMARY `!binary` tag (not the canonical
  # `!!binary`), which the YAML core schema won't auto-decode.
  def self.load_cassette(name : String) : Array(Interaction)
    path = File.join(CASSETTE_DIR, "#{name}.yml")
    unless File.exists?(path)
      raise "missing cassette #{path} (run scripts/fetch-cassettes.sh first)"
    end

    document = YAML::Nodes.parse(File.read(path))
    root = document.nodes.first? || raise "empty cassette #{path}"
    interactions = mapping_fetch(root, "http_interactions")
    raise "no http_interactions in #{path}" unless interactions.is_a?(YAML::Nodes::Sequence)

    interactions.nodes.map do |node|
      request = mapping_fetch(node, "request") || raise "interaction without request in #{path}"
      response = mapping_fetch(node, "response") || raise "interaction without response in #{path}"
      status = mapping_fetch(response, "status") || raise "response without status in #{path}"

      Interaction.new(
        method: scalar_value(mapping_fetch(request, "method")),
        uri: scalar_value(mapping_fetch(request, "uri")),
        request_body: body_string(request),
        status: scalar_value(mapping_fetch(status, "code")).to_i,
        response_body: body_string(response)
      )
    end
  end

  private def self.mapping_fetch(node : YAML::Nodes::Node?, key : String) : YAML::Nodes::Node?
    return nil unless node.is_a?(YAML::Nodes::Mapping)

    node.nodes.each_slice(2) do |pair|
      entry_key, entry_value = pair
      return entry_value if entry_key.is_a?(YAML::Nodes::Scalar) && entry_key.value == key
    end
    nil
  end

  # Extracts a scalar's string value, Base64-decoding VCR's `!binary`
  # tagged bodies (whitespace stripped first — block scalars keep their
  # newlines).
  private def self.scalar_value(node : YAML::Nodes::Node?) : String
    raise "expected a scalar cassette node, got #{node.class}" unless node.is_a?(YAML::Nodes::Scalar)

    if node.tag.in?("!binary", "tag:yaml.org,2002:binary")
      String.new(Base64.decode(node.value.gsub(/\s+/, "")))
    else
      node.value
    end
  end

  private def self.body_string(section : YAML::Nodes::Node) : String
    body = mapping_fetch(section, "body")
    string = mapping_fetch(body, "string")
    string ? scalar_value(string) : ""
  end

  private def handle(context : HTTP::Server::Context)
    request = context.request
    body = request.body.try(&.gets_to_end) || ""

    if interaction = @interactions.find { |candidate| matches?(candidate, request, body) }
      context.response.status_code = interaction.status
      context.response.content_type = "application/json; charset=utf-8"
      context.response.print interaction.response_body
    else
      @unmatched << "#{request.method} #{request.resource} (body #{body.inspect})"
      context.response.status_code = 501
    end
  end

  private def matches?(interaction : Interaction, request : HTTP::Request, body : String) : Bool
    return false unless interaction.method.compare(request.method, case_insensitive: true).zero?

    recorded = URI.parse(interaction.uri)
    return false unless recorded.path == request.path
    return false unless query_pairs(recorded.query) == query_pairs(request.query)

    json_equal?(interaction.request_body, body)
  end

  private def query_pairs(query : String?) : Array({String, String})
    return [] of {String, String} unless query

    URI::Params.parse(query).map { |key, value| {key, value} }.sort!
  end

  # Compares two bodies semantically when both parse as JSON, and
  # byte-for-byte otherwise (empty matches empty).
  private def json_equal?(recorded : String, actual : String) : Bool
    return true if recorded == actual

    begin
      JSON.parse(recorded) == JSON.parse(actual)
    rescue JSON::ParseException
      false
    end
  end
end
