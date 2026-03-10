# frozen_string_literal: true

require "json"

module Master3
  module Introspection
    class Friction
      def initialize(root:)
        @path    = File.join(root, ".master3", "friction.jsonl")
        @records = []
      end

      def record(event:, context: nil)
        entry = { ts: Time.now.to_i, event:, context: }
        @records << entry
        File.open(@path, "a") { |f| f.puts(JSON.generate(entry)) }
      end

      def summary
        return "(no friction recorded)" if @records.empty?
        counts = @records.group_by { |r| r[:event] }.transform_values(&:size)
        counts.sort_by { |_, v| -v }.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
end
