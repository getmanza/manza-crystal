require "http/server"

# A one-shot stub: answers every request with the given status and JSON
# body, and records the last request's method, resource and body so a
# test can assert on what the SDK actually sent.
class StubServer
  getter last_method = ""
  getter last_resource = ""
  getter last_body = ""

  def initialize(@status : Int32, @response_body : String = "{}")
    @server = HTTP::Server.new do |context|
      @last_method = context.request.method
      @last_resource = context.request.resource
      @last_body = context.request.body.try(&.gets_to_end) || ""
      context.response.status_code = @status
      context.response.content_type = "application/json"
      context.response.print @response_body
    end
    @port = @server.bind_tcp("127.0.0.1", 0).port
    server = @server
    spawn { server.listen }
  end

  def client : Zazu::Client
    Zazu::Client.new(api_key: "test", base_url: "http://127.0.0.1:#{@port}")
  end

  def close
    @server.close
  end
end

def with_stub(status : Int32, body : String = "{}", & : StubServer ->)
  stub = StubServer.new(status, body)
  begin
    yield stub
  ensure
    stub.close
  end
end
