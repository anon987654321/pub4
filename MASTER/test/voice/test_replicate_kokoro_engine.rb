# frozen_string_literal: true

require_relative "../test_helper"

class TestReplicateKokoroEngine < Minitest::Test
  def test_available_when_token_env_set
    token = ENV["REPLICATE_API_TOKEN"]
    ENV["REPLICATE_API_TOKEN"] = "test-token-for-engine-check"
    assert Master::Voice::Engines.available?("replicate_kokoro", Master::Voice::Transcendent.load_config)
  ensure
    if token.nil?
      ENV.delete("REPLICATE_API_TOKEN")
    else
      ENV["REPLICATE_API_TOKEN"] = token
    end
  end

  def test_provider_registry_lists_replicate
    providers = Master::Ground::ProviderRegistry.providers
    assert providers.key?(:replicate)
    assert_includes providers[:replicate][:strengths], :tts
  end
end
