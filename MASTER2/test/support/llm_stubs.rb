# frozen_string_literal: true

# LLM stubbing helpers for offline testing
# Usage: call stub_llm_ask in test setup to avoid needing a real API key
module LLMStubs
  # Stub LLM.ask to return a successful response
  def stub_llm_ask(content: "Test response", cost: 0.001)
    result = MASTER::Result.ok(
      content: content,
      tokens_in: 100,
      tokens_out: 50,
      cost: cost,
      streamed: false
    )

    MASTER::LLM.define_singleton_method(:ask) do |*_args, **_opts|
      result
    end
  end

  # Stub LLM.ask to return a sequence of responses (one per call)
  def stub_llm_ask_sequence(responses)
    call_count = 0
    MASTER::LLM.define_singleton_method(:ask) do |*_args, **_opts|
      response = responses[call_count] || responses.last
      call_count += 1
      MASTER::Result.ok(
        content: response,
        tokens_in: 100,
        tokens_out: 50,
        cost: 0.001,
        streamed: false
      )
    end
  end

  # Stub LLM.ask to return an error
  def stub_llm_ask_failure(error: "Model unavailable")
    MASTER::LLM.define_singleton_method(:ask) do |*_args, **_opts|
      MASTER::Result.err(error)
    end
  end

  # Restore the original LLM.ask method after stubbing
  def restore_llm_ask
    MASTER::LLM.singleton_class.remove_method(:ask) if MASTER::LLM.singleton_class.method_defined?(:ask)
  end
end
