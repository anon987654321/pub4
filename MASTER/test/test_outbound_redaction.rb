# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "securerandom"
require "socket"

# The Redactor stood on the log and persistence paths only; the outbound
# provider call was the path where a quoted secret actually leaves the
# machine. The ollama lane is exercised against a real socket rather than a
# stubbed sender, because the wiring is what is under test — a stub proves
# the stub.
class TestOutboundRedaction < Minitest::Test
  TOKEN = "sk-#{SecureRandom.alphanumeric(40)}"

  class FakeBus
    attr_reader :events

    def initialize = @events = []
    def publish(name, payload = nil, **kwargs) = @events << [name, payload || kwargs]
  end

  class FakeSession
    def record_cost(*, **)
    end
  end

  # A one-shot HTTP server on an ephemeral port. It answers whatever it is
  # given and records the request body, so the test can assert what MASTER
  # actually sent.
  class LocalStub
    attr_reader :port, :request

    def initialize
      @server = TCPServer.new("127.0.0.1", 0)
      @port = @server.addr[1]
      @thread = Thread.new { serve }
    end

    def close
      @thread&.kill
      @server.close unless @server.closed?
    end

    private

    def serve
      loop do
        socket = @server.accept
        headers = +""
        headers << socket.gets.to_s until headers.end_with?("\r\n\r\n") || socket.eof?
        length = headers[/content-length:\s*(\d+)/i, 1].to_i
        @request = JSON.parse(socket.read(length).to_s)
        body = JSON.generate("message" => { "content" => "ok" }, "done" => true, "eval_count" => 1)
        socket.print("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
                     "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        socket.close
      end
    rescue StandardError
      nil
    end
  end

  def test_message_rows_are_redacted_without_mutating_the_caller
    dispatcher = Master::Review::LLMDispatcher.allocate
    rows = [{ role: "user", content: "read the key #{TOKEN}" }].freeze

    redacted = dispatcher.send(:redact_outbound_messages, rows)

    assert_includes redacted.first[:content], "[REDACTED]"
    refute_includes redacted.first[:content], TOKEN
    assert_includes rows.first[:content], TOKEN, "the caller's row stays untouched"
  end

  def test_a_non_hash_row_and_structured_content_pass_through_untouched
    dispatcher = Master::Review::LLMDispatcher.allocate
    blocks = [{ "type" => "text", "text" => TOKEN }]

    rows = dispatcher.send(:redact_outbound_messages,
                           ["plain", { role: "user", content: TOKEN },
                            { role: "user", content: blocks }])

    assert_equal "plain", rows.first
    assert_includes rows[1][:content], "[REDACTED]"
    assert_equal blocks, rows.last[:content], "structured content is not flattened by #to_s"
  end

  def test_an_ollama_call_sends_a_redacted_prompt_and_system
    stub = LocalStub.new
    dispatcher = Master::Review::LLMDispatcher.allocate
    dispatcher.instance_variable_set(:@session, FakeSession.new)
    dispatcher.instance_variable_set(:@bus, FakeBus.new)
    dispatcher.instance_variable_set(:@tools, [])
    ENV["OLLAMA_BASE_URL"] = "http://127.0.0.1:#{stub.port}"

    result = dispatcher.send(:send_llm_request, "ollama:llama3:latest",
                             [{ role: "user", content: "the key is #{TOKEN}" }],
                             system: "Bearer #{TOKEN}")

    assert_predicate result, :ok?
    sent = stub.request
    refute_includes JSON.generate(sent), TOKEN, "the token must not leave the process"
    system_row = sent["messages"].find { |row| row["role"] == "system" }
    user_row = sent["messages"].find { |row| row["role"] == "user" }
    assert_equal "[REDACTED]", system_row["content"]
    assert_includes user_row["content"], "[REDACTED]"
    refute_includes user_row["content"], TOKEN
  ensure
    ENV.delete("OLLAMA_BASE_URL")
    stub&.close
  end
end
