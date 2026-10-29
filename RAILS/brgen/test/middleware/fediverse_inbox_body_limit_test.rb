# frozen_string_literal: true

require "test_helper"
require "stringio"

class FediverseInboxBodyLimitTest < ActiveSupport::TestCase
  class TrackingInput < StringIO
    attr_reader :bytes_read

    def initialize(value)
      super(value)
      @bytes_read = 0
    end

    def read(length = nil, outbuf = nil)
      chunk = super
      @bytes_read += chunk.bytesize if chunk
      chunk
    end

    def gets(*arguments, **keywords)
      chunk = super
      @bytes_read += chunk.bytesize if chunk
      chunk
    end
  end

  setup do
    @calls = 0
    @app = lambda do |env|
      @calls += 1
      [ 200, { "content-type" => "text/plain" }, [ env.fetch("rack.input").read.to_s ] ]
    end
    @middleware = Fediverse::InboxBodyLimit.new(@app)
  end

  def env(path: "/inbox", method: "POST", body:, content_length: nil)
    {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "CONTENT_LENGTH" => content_length.to_s,
      "rack.input" => TrackingInput.new(body)
    }
  end

  test "inbox controller and middleware share one byte limit" do
    assert_equal Fediverse::InboxBodyLimit::MAX_BYTES, Fediverse::InboxesController::MAX_BODY
  end

  test "declared oversized body is rejected without reading the input" do
    input = TrackingInput.new("x" * (Fediverse::InboxBodyLimit::MAX_BYTES + 1))
    request = {
      "REQUEST_METHOD" => "POST", "PATH_INFO" => "/inbox",
      "CONTENT_LENGTH" => (Fediverse::InboxBodyLimit::MAX_BYTES + 1).to_s,
      "rack.input" => input
    }

    status, _headers, body = @middleware.call(request)

    assert_equal 413, status
    assert_equal "Request body too large", body.join
    assert_equal 0, input.bytes_read
    assert_equal 0, @calls
  end

  test "lengthless oversized body stops after one byte beyond the cap" do
    input = TrackingInput.new("x" * (Fediverse::InboxBodyLimit::MAX_BYTES + 10))
    request = {
      "REQUEST_METHOD" => "POST", "PATH_INFO" => "/inbox",
      "CONTENT_LENGTH" => "", "rack.input" => input
    }

    status, _headers, body = @middleware.call(request)

    assert_equal 413, status
    assert_equal "Request body too large", body.join
    assert_equal Fediverse::InboxBodyLimit::MAX_BYTES + 1, input.bytes_read
    assert_equal 1, @calls
  end

  test "an exactly capped body succeeds when Content-Length is absent" do
    input = TrackingInput.new("x" * Fediverse::InboxBodyLimit::MAX_BYTES)
    request = {
      "REQUEST_METHOD" => "POST", "PATH_INFO" => "/inbox",
      "CONTENT_LENGTH" => "", "rack.input" => input
    }

    status, _headers, body = @middleware.call(request)

    assert_equal 200, status
    assert_equal Fediverse::InboxBodyLimit::MAX_BYTES, body.join.bytesize
    assert_equal Fediverse::InboxBodyLimit::MAX_BYTES, input.bytes_read
  end

  test "the per-user inbox gets the same protection" do
    request = env(
      path: "/users/kari/inbox",
      body: "x" * (Fediverse::InboxBodyLimit::MAX_BYTES + 1),
      content_length: Fediverse::InboxBodyLimit::MAX_BYTES + 1
    )

    status, = @middleware.call(request)

    assert_equal 413, status
    assert_equal 0, @calls
  end

  test "invalid declared content length fails with a client error" do
    request = env(path: "/inbox", body: "x", content_length: "not-a-length")

    status, _headers, body = @middleware.call(request)

    assert_equal 400, status
    assert_equal "Invalid Content-Length", body.join
    assert_equal 0, @calls
  end

  test "unrelated requests do not get the inbox limit" do
    body = "x" * (Fediverse::InboxBodyLimit::MAX_BYTES + 1)
    request = env(path: "/posts", body: body, content_length: body.bytesize)

    status, _headers, response = @middleware.call(request)

    assert_equal 200, status
    assert_equal body.bytesize, response.join.bytesize
    assert_equal body.bytesize, request.fetch("rack.input").bytes_read
  end

  test "output buffers return nil at end of a length-bounded read" do
    limited = Fediverse::InboxBodyLimit::LimitedInput.new(StringIO.new("x"), 10)
    buffer = +""

    assert_equal "x", limited.read(1, buffer)
    assert_nil limited.read(1, buffer)
    assert_equal "", buffer
  end

  test "negative read lengths cannot turn a bounded read into an unbounded one" do
    input = TrackingInput.new("x" * 100)
    limited = Fediverse::InboxBodyLimit::LimitedInput.new(input, 10)

    assert_raises(ArgumentError) { limited.read(-1) }
    assert_equal 0, input.bytes_read
  end
end
