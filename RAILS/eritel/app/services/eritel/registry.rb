# frozen_string_literal: true

module Eritel
  class Registry
    PROVIDERS = {
      "simulator" => RegistrySimulator,
      "disabled" => RegistryAdapter,
      "authorized" => RegistryAdapter
    }.freeze

    def self.current
      provider = Rails.application.config.x.registry_provider.to_s
      klass = PROVIDERS.fetch(provider) do
        raise ArgumentError, "unsupported registry provider: #{provider}"
      end

      klass.new(endpoint: Rails.application.config.x.registry_endpoint)
    end
  end
end
