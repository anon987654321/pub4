# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ProviderCanaryTest < Minitest::Test
  class Router
    def pool(wait:) = wait ? [] : %w[claude-cli:opus ollama:qwen3 openai:gpt-4.1 claude-cli:sonnet]
    def api_provider_for(model) = model.start_with?("openai:") ? "openai" : nil
  end

  class Agent
    attr_reader :models, :response_mode

    def initialize(response_mode: :echo)
      @models = []
      @response_mode = response_mode
    end

    def ask_once(prompt, **kwargs)
      @models << [kwargs.fetch(:model), kwargs.fetch(:failover), kwargs.fetch(:law)]
      return "wrong response" if @response_mode == :wrong

      prompt.sub(/Reply with (.+) and nothing else./, "\1")
    end
  end

  class Bus
    attr_reader :events

    def initialize = @events = []

    def publish(event, **payload)
      @events << [event.to_s, payload]
    end
  end

  def test_provider_canary_source_compiles
    path = File.expand_path("../lib/cli/routing/provider_canary.rb", __dir__)
    source = File.read(path)
    assert_silent { RubyVM::InstructionSequence.compile(source, path) }
  end

  def test_provider_domain_splits_colon_slash_and_backslash_model_ids
    canary = Master::CLI::Routing::ProviderCanary.new(
      agent: Agent.new,
      router: Router.new,
    )

    assert_equal "openai", canary.provider_domain("openai:gpt-4.1")
    assert_equal "openai", canary.provider_domain("openai/gpt-4.1")
    assert_equal "openai", canary.provider_domain("openai\\gpt-4.1")
  end

  def test_candidates_keep_one_model_per_provider_domain
    canary = Master::CLI::Routing::ProviderCanary.new(
      agent: Agent.new,
      router: Router.new,
      max_providers: 3,
    )

    assert_equal %w[claude-cli:opus ollama:qwen3 openai:gpt-4.1], canary.candidates
  end

  def test_malformed_canary_response_is_recorded_as_health_failure
    agent = Agent.new(response_mode: :wrong)
    bus = Bus.new

    Dir.mktmpdir do |dir|
      health = Master::CLI::Routing::ProviderHealth.new(path: File.join(dir, "health.ndjson"))

      canary = Master::CLI::Routing::ProviderCanary.new(
        agent:,
        router: Router.new,
        event_bus: bus,
        health:,
        max_providers: 1,
      )

      assert_equal "0/1 canaries passed", canary.run
      assert_equal :canary_validation_failure, health.latest_event("claude-cli:opus")["status"].to_sym
    end
  end

  def test_run_uses_ask_once_without_failover_and_publishes_results
    agent = Agent.new
    bus = Bus.new
    canary = Master::CLI::Routing::ProviderCanary.new(
      agent:,
      router: Router.new,
      event_bus: bus,
      max_providers: 2,
    )

    assert_equal "2/2 canaries passed", canary.run
    assert_equal [["claude-cli:opus", false, false], ["ollama:qwen3", false, false]], agent.models
    assert bus.events.any? { |name, payload| name == "provider:canary" && payload[:status] == :success }
    assert bus.events.any? { |name, _| name == "provider:canary_summary" }
  end
end
