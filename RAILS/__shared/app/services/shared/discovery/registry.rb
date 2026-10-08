# frozen_string_literal: true

module Shared
  module Discovery
    # Which providers an app draws from.
    #
    # Providers accumulate per app rather than replacing one another. Storing
    # one provider per key and reading it back through a plural accessor
    # means the second registration silently discards the first, and the
    # symptom is a rail that is merely shorter than it should be -- nothing
    # raises and nothing logs.
    #
    # A provider is anything answering `call(context)` with an array of
    # Candidates, so a test can register a lambda.
    class Registry
      class << self
        def register(app, provider)
          raise ArgumentError, "provider must respond to call" unless provider.respond_to?(:call)

          mutex.synchronize { providers[app.to_sym] |= [provider] }
          provider
        end

        # Falls back to :general, so a provider registered for everyone does
        # not have to be registered once per app.
        def providers_for(app)
          mutex.synchronize { (providers[app.to_sym] + providers[:general]).uniq }
        end

        def clear!
          mutex.synchronize { @providers = nil }
        end

        private

        def providers
          @providers ||= Hash.new { |hash, key| hash[key] = [] }
        end

        def mutex
          @mutex ||= Mutex.new
        end
      end
    end
  end
end
