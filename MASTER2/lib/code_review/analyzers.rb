# frozen_string_literal: true

module CodeReview
  module Analyzers
    @registry = {}

    class << self
      def register(name, klass)
        raise ArgumentError, "name must be provided" if name.nil? || name.to_s.strip.empty?
        raise ArgumentError, "klass must be provided" if klass.nil?

        @registry[name.to_sym] = klass
      end

      def fetch(name)
        @registry.fetch(name.to_sym)
      end

      def registered?(name)
        @registry.key?(name.to_sym)
      end

      def all
        @registry.values
      end

      def registry
        @registry.dup
      end

      def clear!
        @registry.clear
      end
    end
  end
end

require_relative "analyzers/base"
require_relative "analyzers/rubocop"
require_relative "analyzers/reek"
require_relative "analyzers/brakeman"