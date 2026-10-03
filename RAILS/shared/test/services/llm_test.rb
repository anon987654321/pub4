# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/llm"

class SharedLlmTest < Minitest::Test
  def test_default_provider_reads_the_openrouter_key
    old = ENV["OPENROUTER_API_KEY"]
    ENV["OPENROUTER_API_KEY"] = "test-key"

    assert Shared::Llm.configured?
  ensure
    ENV["OPENROUTER_API_KEY"] = old
  end

  def test_provider_readiness_reads_the_selected_provider_key
    old = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-key"

    assert Shared::Llm.configured?(provider: :groq)
  ensure
    ENV["GROQ_API_KEY"] = old
  end

  def test_unknown_providers_fail_explicitly
    assert_raises(KeyError) { Shared::Llm.key_env_for(:unknown) }
  end
end
