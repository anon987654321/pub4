# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "socket"

# The local tier could be enabled and could not answer.
#
# models.yml has declared `ollama:` ids since the tier was written, and
# ModelRouter learned to drop them when OLLAMA_BASE_URL is unset — but
# provider_availability.rb's own comment records the other half: with no branch
# in the dispatcher, an id that *passed* the gate fell through to RubyLLM, which
# handed `ollama:llama3:latest` to OpenRouter and got an error. Enabling the tier
# was the way to break it.
#
# Every case here runs against a real socket rather than a stubbed client,
# because what was wrong was the wiring and a stub would have proved the stub.
class TestOllamaSender < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize = @events = []
    def publish(name, payload = nil, **kwargs) = @events << [name, payload || kwargs]
  end

  class FakeSession
    attr_reader :costs

    def initialize = @costs = []
    def record_cost(amount, model:, tokens:) = @costs << { amount:, model:, tokens: }
  end

  # A one-shot HTTP server on an ephemeral port. It answers whatever it is given
  # and records the request body, so a test can assert what MASTER actually sent.
  class Stub
    attr_reader :port, :requests

    def initialize(status: "200 OK", body: "", chunked: false)
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @requests = []
      @thread = Thread.new { serve(status, body, chunked) }
    end

    def close
      @thread&.kill
      @server.close unless @server.closed?
    end

    private

    def serve(status, body, chunked)
      loop do
        socket = @server.accept
        @requests << read_request(socket)
        socket.print("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n" \
                     "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n")
        # Written in pieces so the streaming path has more than one read to do.
        chunked ? body.each_line { |line| socket.print(line) } : socket.print(body)
        socket.close
      end
    rescue StandardError
      nil
    end

    def read_request(socket)
      headers = +""
      headers << socket.gets.to_s until headers.end_with?("\r\n\r\n") || socket.eof?
      length = headers[/content-length:\s*(\d+)/i, 1].to_i
      JSON.parse(socket.read(length).to_s)
    rescue StandardError
      {}
    end
  end

  def test_a_reply_comes_back_with_its_tokens_recorded
    body = JSON.generate(
      "message" => { "role" => "assistant", "content" => "Deep shade blue." },
      "done" => true, "prompt_eval_count" => 19, "eval_count" => 5,
    )
    with_stub(body:) do |sender, session, bus, stub|
      result = ask(sender, "ollama:llama3:latest", "What colour is the sky?")

      assert_predicate result, :ok?
      assert_equal "Deep shade blue.", result.value!
      assert_equal 24, session.costs.first[:tokens]
      assert_in_delta 0.0, session.costs.first[:amount], 0.0001, "local inference costs nothing"
      assert(bus.events.any? { |name, _| name == "llm:cost" })
      # The prefix is stripped and the system prompt leads, or Ollama answers as
      # a model called `ollama:llama3`.
      sent = stub.requests.first
      assert_equal "llama3:latest", sent["model"]
      assert_equal %w[system user], sent["messages"].map { |row| row["role"] }
    end
  end

  def test_a_stream_yields_each_piece_and_assembles_the_whole
    body = [
      { "message" => { "content" => "Oslo" }, "done" => false },
      { "message" => { "content" => " exists." }, "done" => false },
      { "message" => { "content" => "" }, "done" => true, "prompt_eval_count" => 8, "eval_count" => 3 },
    ].map { |row| "#{JSON.generate(row)}\n" }.join

    with_stub(body:, chunked: true) do |sender, session, _bus, _stub|
      pieces = []
      result = ask(sender, "ollama:llama3:latest", "Name a city.", stream: true) { |piece| pieces << piece }

      assert_equal "Oslo exists.", result.value!
      assert_equal ["Oslo", " exists."], pieces
      assert_equal 11, session.costs.first[:tokens]
    end
  end

  # Enabled-and-wrong and enabled-and-down are different operator actions, so
  # they are different messages rather than one generic provider error.
  def test_a_missing_model_names_the_model
    with_stub(status: "404 Not Found", body: %({"error":"model 'ghost' not found"})) do |sender, _s, _b, _stub|
      result = ask(sender, "ollama:ghost", "hi")

      assert_predicate result, :err?
      assert_equal :provider_error, result.category
      assert_includes result.message, "ghost"
    end
  end

  def test_an_unreachable_daemon_names_the_url
    stub = Stub.new
    port = stub.port
    stub.close
    sender, = build_sender
    ENV["OLLAMA_BASE_URL"] = "http://127.0.0.1:#{port}"
    result = ask(sender, "ollama:llama3:latest", "hi")

    assert_predicate result, :err?
    assert_equal :provider_error, result.category
    assert_includes result.message, "127.0.0.1:#{port}"
  ensure
    ENV.delete("OLLAMA_BASE_URL")
  end

  def test_an_unparseable_reply_is_an_llm_failure_not_a_crash
    with_stub(body: "not json at all") do |sender, _s, _b, _stub|
      result = ask(sender, "ollama:llama3:latest", "hi")

      assert_predicate result, :err?
      assert_equal :llm_failure, result.category
    end
  end

  # The defect itself: the dispatcher had no branch, so an enabled local id went
  # to RubyLLM and out to a paid provider.
  def test_the_dispatcher_routes_an_ollama_id_before_ruby_llm
    dispatcher = Master::Review::LLMDispatcher.allocate
    reached = []
    dispatcher.define_singleton_method(:send_ollama) { |model, *, **, &_| reached << model }
    dispatcher.define_singleton_method(:send_ruby_llm) { |model, *, **, &_| reached << "ruby_llm:#{model}" }
    dispatcher.define_singleton_method(:system_prompt) { "" }
    dispatcher.define_singleton_method(:llm_tools) { |_| [] }
    dispatcher.instance_variable_set(:@tools, [])

    dispatcher.send(:send_llm_request, "ollama:llama3:latest", [{ role: "user", content: "hi" }])

    assert_equal ["ollama:llama3:latest"], reached
  end

  private

  def build_sender
    sender = Master::Review::LLMDispatcher.allocate
    session = FakeSession.new
    bus = FakeBus.new
    sender.instance_variable_set(:@session, session)
    sender.instance_variable_set(:@bus, bus)
    [sender, session, bus]
  end

  def ask(sender, model, text, stream: false, &blk)
    sender.send(:send_ollama, model, [{ role: "user", content: text }], sys: "Be brief.", stream:, &blk)
  end

  def with_stub(status: "200 OK", body: "", chunked: false)
    stub = Stub.new(status:, body:, chunked:)
    sender, session, bus = build_sender
    ENV["OLLAMA_BASE_URL"] = "http://127.0.0.1:#{stub.port}"
    yield(sender, session, bus, stub)
  ensure
    ENV.delete("OLLAMA_BASE_URL")
    stub&.close
  end
end
