# frozen_string_literal: true

module Providers
  Response = Struct.new(:provider, :ok, :body, :error, keyword_init: true)

  class FallbackChain
    def initialize(providers)
      @providers = providers
    end

    def call(prompt, **options)
      errors = []
      @providers.each do |provider|
        response = provider.call(prompt, **options)
        return Response.new(provider: provider.name, ok: true, body: response, error: nil)
      rescue StandardError => error
        errors << "#{provider.name}: #{error.class}: #{error.message}"
      end
      Response.new(provider: nil, ok: false, body: nil, error: errors.join("; "))
    end
  end
end
