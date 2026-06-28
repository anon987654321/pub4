# frozen_string_literal: true

require "fileutils"
require "json"

module Master
  module Trace
    # Prompt-cache hit ratio — OpenCrabs /usage card parity.
    module CacheEfficiency
      @mutex = Mutex.new
      @totals = { input: 0, cached: 0, cache_write: 0, calls: 0 }

      module_function

      def record(input:, cached: 0, cache_write: 0)
        return if input.to_i <= 0 && cached.to_i <= 0

        @mutex.synchronize do
          @totals[:input] += input.to_i
          @totals[:cached] += cached.to_i
          @totals[:cache_write] += cache_write.to_i
          @totals[:calls] += 1
          persist!
        end
      rescue StandardError => e
        Ground::Swallow.log(e, context: "cache_efficiency.record")
      end

      def snapshot
        data = @mutex.synchronize { @totals.dup }
        input = data[:input].to_i
        cached = data[:cached].to_i
        pct = input.positive? ? ((cached.to_f / input) * 100).round(1) : 0.0
        {
          efficiency_pct: pct,
          input_tokens: input,
          cached_tokens: cached,
          cache_write_tokens: data[:cache_write].to_i,
          calls: data[:calls].to_i,
        }
      end

      def reset!
        @mutex.synchronize do
          @totals = { input: 0, cached: 0, cache_write: 0, calls: 0 }
          persist!
        end
      end

      def path
        File.join(Master::ROOT, ".master", "cache_efficiency.json")
      end

      def load!
        return unless File.file?(path)
        data = JSON.parse(File.read(path))
        @mutex.synchronize { @totals = data.transform_keys(&:to_sym) }
      rescue StandardError
        nil
      end

      def persist!
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(@totals))
      rescue StandardError
        nil
      end
    end
  end
end
