# frozen_string_literal: true

module Master
  module Judge
  module Scan
    Finding = Data.define(:rule, :message, :line, :severity, :fix, :tags) do
      def self.build(rule:, message:, line:, severity: :warning, fix: nil, tags: [])
        new(rule:, message:, line:, severity:, fix:, tags:)
      end

      def [](key)
        public_send(key)
      end

      def to_h
        { rule:, message:, line:, severity:, fix:, tags: }
      end

      def merge(extras) = to_h.merge(extras)
    end
  end
  end
end
