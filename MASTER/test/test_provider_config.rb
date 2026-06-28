# frozen_string_literal: true

require_relative "test_helper"

class TestProviderConfig < Minitest::Test
  def test_api_key_specs_are_loaded_from_yaml
    specs = Master.api_key_specs

    assert_includes specs, [:openai_api_key, "OPENAI_API_KEY", 40]
    assert_includes specs, [:gemini_api_key, "GOOGLE_API_KEY", 20]
    assert_includes specs, [:gemini_api_key, "GEMINI_API_KEY", 20]
  end

  def test_minimum_lengths_are_provider_specific
    previous = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = "x" * 40
    refute Master.api_key_present?("ANTHROPIC_API_KEY")
    ENV["ANTHROPIC_API_KEY"] = "x" * 80
    assert Master.api_key_present?("ANTHROPIC_API_KEY")
  ensure
    ENV["ANTHROPIC_API_KEY"] = previous
  end

  def test_runtime_registry_uses_yaml_as_its_provider_source
    Master::Ground::ProviderRegistry.reset!
    providers = Master::Ground::ProviderRegistry.providers

    assert_equal "gpt-5.5-thinking", providers.dig(:openai, :default_model)
    refute providers.key?(:schema)
  ensure
    Master::Ground::ProviderRegistry.reset!
  end
end
