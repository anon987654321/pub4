# frozen_string_literal: true

module Master
  module Now
  # PipelineContext — canonical key inventory and type contracts for the pipeline Hash.
  # validate! enforces intake prerequisites. assert_stage! enforces inter-stage contracts.
  module PipelineContext
    INTAKE_REQUIRED = %i[user_message].freeze

    STAGE_KEYS = {
      intake:  %i[intent command args message],
      infer:   %i[task_type pressure original_message],
      route:   %i[handler model last_tool_tier],
      execute: %i[output tool_calls written_files source],
      council: %i[council_feedback],
      lint:    %i[lint_report lint_error],
      review:  %i[review_error],
      enhance: %i[pre_enhanced],
      render:  %i[rendered voice],
      memory:  []
    }.freeze

    ALL_KEYS = (INTAKE_REQUIRED + STAGE_KEYS.values.flatten).uniq.freeze

    # Keys that MUST exist before each stage starts.
    STAGE_PREREQUISITES = {
      infer:   %i[user_message],
      route:   %i[user_message],
      execute: %i[user_message handler],
      council: %i[output],
      lint:    %i[output],
      render:  %i[output]
    }.freeze

    # Expected Ruby types per key. Enforced by assert_stage!
    KEY_TYPES = {
      user_message: [String],
      task_type:    [String, Symbol, NilClass],
      handler:      [Symbol, String, NilClass],
      model:        [String, NilClass],
      output:       [String, NilClass],
      pressure:     [TrueClass, FalseClass, NilClass],
      lint_report:  [Array, NilClass],
      voice:        [String, NilClass]
    }.freeze

    module_function

    def validate!(ctx)
      missing = INTAKE_REQUIRED.reject { |k| ctx.key?(k) }
      return if missing.empty?
      raise ArgumentError, "PipelineContext missing required keys: #{missing.join(', ')}"
    end

    # Call at the entry of each named stage. Raises if prerequisites are absent
    # or if present values violate declared types.
    def assert_stage!(ctx, stage)
      prereqs = STAGE_PREREQUISITES.fetch(stage, [])
      missing = prereqs.reject { |k| ctx.key?(k) }
      raise ArgumentError, "#{stage} stage missing prerequisites: #{missing.join(', ')}" unless missing.empty?
      KEY_TYPES.each do |key, allowed|
        next unless ctx.key?(key)
        value = ctx[key]
        next if allowed.any? { |t| value.is_a?(t) }
        raise TypeError, "ctx[#{key.inspect}] expected #{allowed.map(&:name).join('|')}, got #{value.class}"
      end
    end

    def fetch!(ctx, key)
      ctx.fetch(key) { raise KeyError, "PipelineContext: missing key #{key.inspect}" }
    end

    def build(user_message:, **opts)
      { user_message:, on_chunk: opts[:on_chunk] }.merge(opts)
    end
  end
  end
end
