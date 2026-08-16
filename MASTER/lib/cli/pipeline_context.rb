# frozen_string_literal: true

require_relative "pipeline_context/factory_methods"

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
        rendered output_findings voice
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
        voice: [String, NilClass],
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
        @data = hash.freeze
      end

      # Read by symbol or string key — Hash-compatible subscript.
      def [](key)
        @data[key.to_sym]
      end

      # Struct-style accessors for all known keys.
      KNOWN_KEYS.each do |key|
        define_method(key) { @data[key] }
      end

      def key?(key) = @data.key?(key.to_sym)
      def to_h = @data.dup
      # already immutable
      def freeze = self

      # Immutable update — returns a new PipelineContext merging overrides.
      # Accepts a Hash or another PipelineContext (e.g. when combining parallel
      # stage results), mirroring the Hash-compatible #[]/#to_h/#wrap surface.
      def merge(overrides = {})
        overrides = overrides.to_h if overrides.is_a?(PipelineContext)
        PipelineContext.new(@data.merge(normalize_overrides(overrides)))
      end

      def ==(other)
        other.is_a?(PipelineContext) && @data == other.to_h
      end

      def inspect = "#<PipelineContext #{@data.inspect}>"

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
