# frozen_string_literal: true

module Master
  module Ground
  module ProviderRegistry
    PROVIDERS = {
      openai: {
        env: %w[OPENAI_API_KEY],
        strengths: %i[reasoning coding multimodal],
        default_model: "gpt-5.5-thinking"
      },
      anthropic: {
        env: %w[ANTHROPIC_API_KEY],
        strengths: %i[coding long_context instruction_following],
        default_model: "claude-sonnet"
      },
      gemini: {
        env: %w[GOOGLE_API_KEY GEMINI_API_KEY],
        strengths: %i[long_context multimodal],
        default_model: "gemini-pro"
      },
      local: {
        env: [],
        strengths: %i[privacy offline cheap],
        default_model: "local"
      }
    }.freeze

    module_function

    def available
      PROVIDERS.select { |_name, cfg| Array(cfg[:env]).empty? || cfg[:env].any? { |key| ENV[key].to_s != "" } }
    end

    def choose(task: :coding)
      candidates = available
      exact = candidates.find { |_name, cfg| cfg[:strengths].include?(task.to_sym) }
      name, cfg = exact || candidates.first || [:local, PROVIDERS[:local]]
      { provider: name, model: cfg[:default_model], strengths: cfg[:strengths] }
    end

    def brief
      "Provider registry: available=#{available.keys.join(', ')}; choose by task strengths, fall back to local."
    end
  end
  end
end
