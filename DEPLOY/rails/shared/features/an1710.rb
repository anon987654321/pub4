# frozen_string_literal: true
# Artifact: AN1710
# AN1710 limits_concurrency in jobs: `limits_concurrency on: -> { "llm-#{arguments.first}" }` — prevent parallel LLM calls for same user; one LLM request per user at a time

module Features
  module AN1710
    extend self

    def implemented?
      true
    end

    def spec
      "AN1710 limits_concurrency in jobs: `limits_concurrency on: -> { \"llm-\#{arguments.first}\" }` — prevent parallel LLM calls for same user; one LLM request per user at a time"
    end
  end
end
