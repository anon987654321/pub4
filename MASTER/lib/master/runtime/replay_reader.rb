# frozen_string_literal: true

require "json"

module Master
  module Runtime
    class ReplayReader
      def initialize(path)
        @path = path
      end

      def events
        return enum_for(:events) unless block_given?
        return unless File.exist?(@path)

        File.foreach(@path) do |line|
          next if line.strip.empty?

          yield JSON.parse(line)
        rescue JSON::ParserError
          next
        end
      end

      def workflow(workflow_id)
        events.select do |event|
          event["workflow_id"] == workflow_id
        end
      end

      def event_types
        events.map { |event| event["event"] }.uniq.sort
      end
    end
  end
end
