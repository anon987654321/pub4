# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/llm"

class SharedLlmTest < Minitest::Test
  test "default provider reads the OpenRouter key" do
    old = ENV["OPENROUTER_API_KEY"]
    ENV["OPENROUTER_API_KEY"] = "test-key"

    assert Shared::Llm.configured?
  ensure
    ENV["OPENROUTER_API_KEY"] = old
  end

  test "provider readiness reads the selected provider key" do
    old = ENV["GROQ_API_KEY"]
    ENV["GROQ_API_KEY"] = "test-key"

    assert Shared::Llm.configured?(provider: :groq)
  ensure
    ENV["GROQ_API_KEY"] = old
  end

  test "unknown providers fail explicitly" do
    assert_raises(KeyError) { Shared::Llm.key_env_for(:unknown) }
  end
end
