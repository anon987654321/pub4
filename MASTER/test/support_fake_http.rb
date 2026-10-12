# frozen_string_literal: true

require "socket"
require "json"

# A plain-socket HTTP/1.1 server for transport tests: no network beyond
# 127.0.0.1, no WEBrick. The block gets (verb, path, headers, body_string) and
# returns [status, json_object]; every request is also recorded in #requests.
class FakeHttp
  Req = Struct.new(:verb, :path, :headers, :body) do
    def json = body.to_s.empty? ? nil : JSON.parse(body)
  end

  attr_reader :requests, :port

  def initialize(&handler)
    @handler = handler
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { serve }
  end

  def url = "http://127.0.0.1:#{@port}"
  def stop = (@server.close unless @server.closed?; @thread.kill)

  private

  def serve
    loop do
      client = @server.accept
      Thread.new(client) { |c| answer(c) }
    end
  rescue IOError, Errno::EBADF
    nil
  end

  def answer(sock)
    verb, path, = sock.gets.to_s.split(" ")
    headers = {}
    while (line = sock.gets) && line != "\r\n"
      key, value = line.split(":", 2)
      headers[key.downcase] = value.to_s.strip
    end
    body = sock.read(headers["content-length"].to_i).to_s
    req = Req.new(verb, path, headers, body)
    @requests << req
    status, payload = @handler.call(req)
    data = payload.nil? ? "" : JSON.generate(payload)
    sock.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{data.bytesize}\r\nConnection: close\r\n\r\n#{data}")
  ensure
    sock.close
  end
end
