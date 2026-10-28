# frozen_string_literal: true

require_relative "test_helper"

# Lane policy that was held twice in Ruby now has one owner in YAML: vision
# families and subscription order in models.yml, key routing in providers.yml.
class TestLanePolicyFromYaml < Minitest::Test
  Selection = Master::Io::LaneSelection

  # A bare gemini-3 id reads images; a blind family never does; the dispatcher
  # asks the same reader.
  def test_vision_families_cover_every_gemini_and_the_dispatcher_agrees
    assert Selection.vision?("gemini-3.1-pro")
    refute Selection.vision?("deepseek-chat")

    dispatcher = Master::Review::LLMDispatcher.allocate
    assert dispatcher.send(:vision_capable?, "gemini-3.1-pro")
  end

  def test_subscription_lanes_come_from_models_yml
    assert_equal %w[claude-cli grok-cli codex-cli agy], Selection.subscription_lanes
  end

  # An owner/name id goes through OpenRouter, a bare id through its vendor.
  def test_api_key_routing_comes_from_providers_yml
    envs = ->(id) { Selection.api_keys.find { |pattern, _envs| pattern.match?(id) }&.last }

    assert_equal %w[OPENROUTER_API_KEY], envs.call("deepseek/deepseek-chat")
    assert_equal %w[DEEPSEEK_API_KEY], envs.call("deepseek-chat")
    assert_equal %w[GOOGLE_API_KEY GEMINI_API_KEY], envs.call("gemini-3.1-pro")
    assert_nil envs.call("mistral-large")
  end
end
