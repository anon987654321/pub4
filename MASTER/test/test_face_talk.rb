# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face/talk"

class TestFaceTalk < Minitest::Test
  Response = Struct.new(:code, :body)

  class Http
    class << self
      attr_accessor :response
    end

    def initialize(*)
    end

    def use_ssl=(_value)
    end

    def open_timeout=(_value)
    end

    def read_timeout=(_value)
    end

    def request(_request) = self.class.response
  end

  Session = Struct.new(:messages) do
    def add_message(role:, content:)
      messages << { role:, content: }
    end
  end

  def session
    Session.new([{ role: :user, content: "hello" }])
  end

  def test_successful_response_becomes_a_result
    Http.response = Response.new(
      "200",
      { "candidates" => [{ "content" => { "parts" => [{ "text" => "Hello." }] } }] }.to_json,
    )

    result = Master::CLI::Face::Talk.ask(session, api_key: "test", http_class: Http)

    assert result.ok?
    assert_equal "Hello.", result.value!
  end

  def test_empty_response_preserves_the_provider_reason
    Http.response = Response.new(
      "200",
      { "candidates" => [{ "finishReason" => "SAFETY" }] }.to_json,
    )

    result = Master::CLI::Face::Talk.ask(session, api_key: "test", http_class: Http)

    assert result.err?
    assert_equal "talk0: empty response (safety)", result.message
  end

  def test_http_failure_exposes_provider_message
    Http.response = Response.new(
      "429",
      { "error" => { "message" => "Resource exhausted" } }.to_json,
    )

    result = Master::CLI::Face::Talk.ask(session, api_key: "test", http_class: Http)

    assert result.err?
    assert_equal "talk0: Resource exhausted", result.message
  end

  def test_failed_reply_is_not_added_to_the_transcript
    Http.response = Response.new(
      "200",
      { "candidates" => [{ "finishReason" => "SAFETY" }] }.to_json,
    )

    target = session
    result = Master::CLI::Face::Talk.reply(target, "make a picture")

    assert result.err?
    assert_equal 2, target.messages.size
    assert_equal :user, target.messages.last[:role]
  end
end
