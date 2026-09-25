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
    assert_match(/\Atalk0: gemini: empty response \(safety\), and no other lane is live — set /, result.message)
  end

  def test_http_failure_exposes_provider_message
    Http.response = Response.new(
      "429",
      { "error" => { "message" => "Resource exhausted" } }.to_json,
    )

    result = Master::CLI::Face::Talk.ask(session, api_key: "test", http_class: Http)

    assert result.err?
    assert_match(/\Atalk0: gemini: Resource exhausted, and no other lane is live/, result.message)
  end

  def test_failed_reply_is_not_added_to_the_transcript
    Http.response = Response.new(
      "200",
      { "candidates" => [{ "finishReason" => "SAFETY" }] }.to_json,
    )

    target = session
    result = Master::CLI::Face::Talk.reply(target, "make a picture", api_key: "test", http_class: Http)

    assert result.err?
    assert_equal 2, target.messages.size
    assert_equal :user, target.messages.last[:role]
  end

  Router = Struct.new(:chain) do
    def fallback_chain(task_type:)
      raise ArgumentError, task_type.to_s unless task_type == :chitchat

      chain
    end

    def cli_lane_model?(id) = id.start_with?("codex-cli:")
  end

  # Answers from a table of model => reply; a reply that is an exception raises.
  class Agent
    attr_reader :asked

    def initialize(replies)
      @replies = replies
      @asked = []
    end

    def ask_once(prompt, system:, law:, model:, failover:)
      @asked << { prompt:, system:, law:, model:, failover: }
      reply = @replies.fetch(model)
      raise reply if reply.is_a?(Exception)

      reply
    end
  end

  def test_gemini_present_answers_without_the_router
    Http.response = Response.new(
      "200",
      { "candidates" => [{ "content" => { "parts" => [{ "text" => "From Gemini." }] } }] }.to_json,
    )
    agent = Agent.new({})

    result = Master::CLI::Face::Talk.ask(session, api_key: "test", http_class: Http,
                                                  router: Router.new(["claude-cli:claude-sonnet-5"]), agent:)

    assert_equal "From Gemini.", result.value!
    assert_empty agent.asked
  end

  def test_without_gemini_a_routed_fast_lane_answers
    router = Router.new(["agy:auto", "web-chat:grok", "codex-cli:auto", "claude-cli:claude-opus-5-5",
                         "gemini-2.5-flash", "claude-cli:claude-sonnet-5"])
    agent = Agent.new("claude-cli:claude-sonnet-5" => "  From Claude.\n")

    result = Master::CLI::Face::Talk.ask(session, api_key: "", router:, agent:)

    assert_equal "From Claude.", result.value!
    assert_equal 1, agent.asked.size
    call = agent.asked.first
    assert_equal "claude-cli:claude-sonnet-5", call[:model]
    assert_equal "user: hello", call[:prompt]
    assert_equal Master::CLI::Face::Talk::SYSTEM, call[:system]
    refute call[:law]
    refute call[:failover]
  end

  def test_gemini_quota_error_falls_through_to_the_next_live_lane
    Http.response = Response.new("429", { "error" => { "message" => "Resource exhausted" } }.to_json)
    router = Router.new(["openrouter/some-model", "ollama:gemma3:4b"])
    agent = Agent.new("openrouter/some-model" => StandardError.new("402 no credit"), "ollama:gemma3:4b" => "Local.")

    result = Master::CLI::Face::Talk.ask(session, api_key: "test", http_class: Http, router:, agent:)

    assert_equal "Local.", result.value!
    assert_equal ["openrouter/some-model", "ollama:gemma3:4b"], agent.asked.map { |call| call[:model] }
  end

  def test_every_lane_failing_names_each_failure
    router = Router.new(["ollama:gemma3:4b"])
    agent = Agent.new("ollama:gemma3:4b" => StandardError.new("connection refused"))

    result = Master::CLI::Face::Talk.ask(session, api_key: "", router:, agent:)

    assert result.err?
    assert_equal "talk0: no lane answered — ollama:gemma3:4b: connection refused", result.message
  end

  def test_no_lane_at_all_says_what_to_set
    result = Master::CLI::Face::Talk.ask(session, api_key: "", router: Router.new(["agy:auto"]), agent: Agent.new({}))

    assert result.err?
    assert_equal :no_api_key, result.category
    assert_equal "talk0: no model is set up — #{Master::CLI::Face::Talk::SETUP}", result.message
  end

  def test_a_slow_lane_is_abandoned_at_its_deadline
    slow = Agent.new({})
    def slow.ask_once(*, **) = sleep(5)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Master::CLI::Face::Talk.ask_lane(slow, "ollama:gemma3:4b", "user: hi", 0.2)

    assert_equal :timeout, result.category
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
  end
end
