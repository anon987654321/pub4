# frozen_string_literal: true

require "digest"
require "json"

module Master
  module Runtime
    module Benchmark
      module_function

      def measure(label:, repeats: 1)
        count = Integer(repeats)
        raise ArgumentError, "repeats must be positive" unless count.positive?

        samples = []
        digest = nil

        count.times do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          value = yield
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          samples << elapsed
          digest = output_digest(value)
        end

        {
          label: label.to_s,
          repeats: count,
          wall_ms: (samples.sum / count * 1000).round(3),
          min_ms: (samples.min * 1000).round(3),
          max_ms: (samples.max * 1000).round(3),
          output_digest: digest,
        }.freeze
      end

      def compare(before, after)
        before_digest = before.fetch(:output_digest)
        after_digest = after.fetch(:output_digest)
        before_ms = before.fetch(:wall_ms).to_f
        after_ms = after.fetch(:wall_ms).to_f

        {
          output_equal: before_digest == after_digest,
          before_ms:,
          after_ms:,
          ratio: before_ms.positive? ? (after_ms / before_ms).round(4) : nil,
          regression: before_ms.positive? && after_ms > before_ms,
        }.freeze
      end

      def output_digest(value)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonicalize(value[key])] }
        when Array
          value.map { |entry| canonicalize(entry) }
        when Symbol
          value.to_s
        else
          value
        end
      end
      private_class_method :canonicalize
    end
  end
end
