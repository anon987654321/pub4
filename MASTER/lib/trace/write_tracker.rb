# frozen_string_literal: true

module Master
  module Trace
    # Accumulates mutation paths per pipeline turn for Lint and post-edit hooks.
    class WriteTracker
      MUTATING_TOOLS = %w[write_file str_replace ast_edit batch_replace replace].freeze

      class << self
        attr_accessor :current
      end

      def initialize(event_bus: nil)
        @bus = event_bus
        @paths = []
        @mutex = Mutex.new
        attach! if @bus
      end

      def reset!
        @mutex.synchronize { @paths.clear }
      end

      def record(path)
        normalized = normalize(path)
        return if normalized.empty?

        @mutex.synchronize { @paths << normalized unless @paths.include?(normalized) }
      end

      def paths
        @mutex.synchronize { @paths.dup }
      end

      private

      def attach!
        @bus.subscribe("tool:after") do |event|
          next unless MUTATING_TOOLS.include?(event[:tool].to_s)
          record(event[:path] || event[:full])
        end
      end

      def normalize(path)
        value = path.to_s.strip
        return "" if value.empty?

        expanded = File.expand_path(value)
        File.exist?(expanded) ? expanded : value
      rescue StandardError
        value
      end
    end
  end
end
