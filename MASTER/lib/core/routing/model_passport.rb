# frozen_string_literal: true

module Master::Core::Routing
  # ModelPassport — a machine-readable profile of a model's identity and capabilities.
  #
  # Passports distinguish between a model's identity (e.g., "Gemma 4") and its
  # execution context (e.g., "Local Ollama" vs "Cloud API").
  class ModelPassport
    attr_reader :identity, :provider, :execution, :capabilities, :health

    def initialize(identity:, provider:, execution:, capabilities: {}, health: :healthy)
      @identity = identity
      @provider = provider
      @execution = execution # :local, :cloud, :external
      @capabilities = capabilities # { coding: 0.9, reasoning: 0.8, ... }
      @health = health
    end

    def healthy?
      @health == :healthy
    end

    def to_h
      {
        identity: @identity,
        provider: @provider,
        execution: @execution,
        capabilities: @capabilities,
        health: @health
      }
    end
  end
end
