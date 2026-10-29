require "http/server"

# A stub API for the example specs, which drive code that calls several
# endpoints: answers each "METHOD /path" with its replies in order (the
# last one repeats), 501 for a route with none, and records every request.
# Not for SDK resources: those replay cassettes.
class RouteStub
  record Request, method : String, path : String, headers : HTTP::Headers, body : String
  record Reply, status : Int32, body : String = "{}", headers : HTTP::Headers = HTTP::Headers.new

  getter requests = [] of Request
  getter port : Int32

  @routes = {} of String => Array(Reply)
  @server : HTTP::Server

  def initialize
    @server = HTTP::Server.new { |context| handle(context) }
    @port = @server.bind_tcp("127.0.0.1", 0).port
    server = @server
    spawn { server.listen }
    Fiber.yield # start listening now: a spec that sends nothing closes the server next
  end

  def url : String
    "http://127.0.0.1:#{@port}"
  end

  # Replaces the replies for `method path`.
  def on(method : String, path : String, *replies : Reply) : Nil
    @routes["#{method} #{path}"] = replies.to_a
  end

  def requests_to(method : String, path : String) : Array(Request)
    requests.select { |request| request.method == method && request.path == path }
  end

  def close
    @server.close
  end

  private def handle(context : HTTP::Server::Context)
    request = context.request
    @requests << Request.new(request.method, request.path, request.headers, request.body.try(&.gets_to_end) || "")

    replies = @routes["#{request.method} #{request.path}"]?
    unless replies && !replies.empty?
      context.response.status_code = 501
      return
    end

    reply = replies.size > 1 ? replies.shift : replies.first
    context.response.status_code = reply.status
    reply.headers.each { |name, values| context.response.headers[name] = values }
    context.response.content_type = "application/json"
    context.response.print reply.body
  end
end

def with_route_stub(& : RouteStub ->)
  stub = RouteStub.new
  begin
    yield stub
  ensure
    stub.close
  end
end
