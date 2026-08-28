# frozen_string_literal: true


module Master
  module CLI
    class PipelineContext
      # Class-level construction/validation helpers — separate from
      # PipelineContext's own instance-level accessor/merge API.
      module FactoryMethods
        def build(user_message:, **opts)
          new({ user_message:, on_chunk: opts[:on_chunk] }.merge(opts))
        end

        def validate!(ctx)
          hash = ctx.is_a?(PipelineContext) ? ctx.to_h : ctx
          missing = REQUIRED.reject { |k| hash.key?(k) }
          raise ArgumentError, "PipelineContext missing required keys: #{missing.join(', ')}" unless missing.empty?
        end

        def assert_stage!(ctx, stage)
          hash = ctx.is_a?(PipelineContext) ? ctx.to_h : ctx
          prereqs = STAGE_PREREQUISITES.fetch(stage, [])
          missing = prereqs.reject { |k| hash.key?(k) }
          raise ArgumentError, "#{stage} stage missing prerequisites: #{missing.join(', ')}" unless missing.empty?
          KEY_TYPES.each do |key, allowed|
            next unless hash.key?(key)
            value = hash[key]
            next if allowed.any? { |t| value.is_a?(t) }
            raise TypeError, "ctx[#{key.inspect}] expected #{allowed.map(&:name).join('|')}, got #{value.class}"
          end
        end

        def fetch!(ctx, key)
          value = ctx[key]
          raise KeyError, "PipelineContext: missing key #{key.inspect}" unless ctx.key?(key)
          value
        end

        # Wrap a plain Hash into a PipelineContext. Skips wrapping if already typed.
        def wrap(hash)
          return hash if hash.is_a?(PipelineContext)
          new(hash)
        end
      end
    end
  end
end

module Master
  module CLI
  # Typed pipeline context — enforces required keys, validates types, provides accessors.
  # Immutable update via #merge (returns new instance). Hash-compatible via [] and #to_h.
    class PipelineContext
      extend FactoryMethods

      # Keys every stage may read or write. Unknown keys raise on construction.
      KNOWN_KEYS = %i[
        user_message on_chunk
        intent command args message original_message inferred_command
        task_type pressure locale infer_confidence
        handler model last_tool_tier
        output tool_calls written_files source
        council_feedback
        review_error review_verdict review_preapproved
        destructive_route
        pre_enhanced
        rendered output_findings
        image felt_sense explicit_run
        channel metadata turn_id
        _timings _parallel_errors _parallel_timeout _stage_error
      ].freeze

      REQUIRED = %i[user_message].freeze

      KEY_TYPES = {
        user_message: [String],
        task_type: [String, Symbol, NilClass],
        model: [String, NilClass],
        output: [String, NilClass],
        output_findings: [Array, NilClass],
        pressure: [TrueClass, FalseClass, NilClass],
        felt_sense: [Hash, NilClass],
      }.freeze

      MAX_OUTPUT_BYTES = 8_192
      MAX_TIMINGS = 20

      # Stage prerequisite contracts — checked before each stage runs.
      STAGE_PREREQUISITES = {
        infer: %i[user_message],
        route: %i[user_message],
        execute: %i[user_message handler],
        council: %i[output],
        lint: %i[output],
        render: %i[output],
      }.freeze

      def initialize(hash)
        unknown = hash.keys - KNOWN_KEYS
        raise KeyError, "PipelineContext: unknown keys #{unknown.inspect}" unless unknown.empty?
        @values = hash.freeze
      end

      # Read by symbol or string key — Hash-compatible subscript.
      def [](key)
        @values[key.to_sym]
      end

      # Struct-style accessors for all known keys.
      KNOWN_KEYS.each do |key|
        define_method(key) { @values[key] }
      end

      def key?(key) = @values.key?(key.to_sym)
      def to_h = @values.dup
      # already immutable
      def freeze = self

      # Immutable update — returns a new PipelineContext merging overrides.
      # Accepts a Hash or another PipelineContext (e.g. when combining parallel
      # stage results), mirroring the Hash-compatible #[]/#to_h/#wrap surface.
      def merge(overrides = {})
        overrides = overrides.to_h if overrides.is_a?(PipelineContext)
        PipelineContext.new(@values.merge(normalize_overrides(overrides)))
      end

      def ==(other)
        other.is_a?(PipelineContext) && @values == other.to_h
      end

      def inspect = "#<PipelineContext #{@values.inspect}>"

      private

      def normalize_overrides(hash)
        data = hash.transform_keys(&:to_sym)
        data[:output] = truncate_output(data[:output]) if data.key?(:output)
        data[:_timings] = cap_timings(data[:_timings]) if data.key?(:_timings)
        data
      end

      def truncate_output(value)
        text = value.to_s
        return value if value.nil? || text.bytesize <= MAX_OUTPUT_BYTES

        text.byteslice(-MAX_OUTPUT_BYTES, MAX_OUTPUT_BYTES)
      end

      def cap_timings(value)
        return value unless value.respond_to?(:to_a)

        value.to_a.last(MAX_TIMINGS).to_h
      end
    end
  end
end
