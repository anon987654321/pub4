# frozen_string_literal: true

require "json"
require "time"

module Master
  module Ground
    class UnfinishedLedger
      LEDGER_PATH = File.join(Master::ROOT, ".master", "unfinished.json").freeze

      def initialize(path: LEDGER_PATH)
        @path = path
        FileUtils.mkdir_p(File.dirname(@path))
      end

      def add(task:, context: nil)
        items = load
        items << { task: task, context: context, ts: Time.now.utc.iso8601 }
        write(items)
      end

      def resolve(task_pattern)
        items = load.reject { |i| i[:task].to_s.match?(task_pattern) }
        write(items)
      end

      def pending
        load
      end

      def top(n = 5)
        load.last(n).reverse
      end

      def empty?
        load.empty?
      end

      private

      def load
        return [] unless File.exist?(@path)
        raw = File.read(@path)
        parsed = JSON.parse(raw, symbolize_names: true)
        Array(parsed)
      rescue JSON::ParserError
        []
      end

      def write(items)
        File.write(@path, JSON.pretty_generate(items))
      end
    end
  end
end
