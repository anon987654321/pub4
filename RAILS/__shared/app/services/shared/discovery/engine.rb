# frozen_string_literal: true

module Shared
  module Discovery
    # Runs every provider for an app and returns the best few candidates.
    #
    # One provider raising must not empty the rail, so each is isolated. What
    # it must not do is fail silently: an empty rail and a broken rail look
    # identical on the page, and this tree's dominant defect is wiring that
    # is declared and never runs. Every failure is logged with the provider
    # that caused it, and `errors` carries them for a caller that wants to
    # decide rather than guess.
    class Engine
      DEFAULT_LIMIT = 8

      attr_reader :errors

      def initialize(context:, providers: nil, limit: DEFAULT_LIMIT)
        @context = context
        @providers = Array(providers || Registry.providers_for(context.vertical))
        @limit = limit.to_i.clamp(1, 50)
        @errors = []
      end

      def call
        candidates = @providers.flat_map { |provider| safely(provider) }
        candidates.select(&:valid?)
                  .sort_by { |candidate| -candidate.score }
                  .first(@limit)
      end

      private

      def safely(provider)
        Array(provider.call(@context))
      rescue StandardError => e
        @errors << { provider: provider.class.name, error: "#{e.class}: #{e.message}" }
        Rails.logger.error("discovery provider failed: #{provider.class}: #{e.class}: #{e.message}") if defined?(Rails)
        []
      end
    end
  end
end
