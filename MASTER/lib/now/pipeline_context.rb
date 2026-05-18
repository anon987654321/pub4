# frozen_string_literal: true

module Master
  module Now
  # PipelineContext — canonical key inventory for the pipeline Hash.
  # Stages pass a plain Hash for compatibility, but all known keys are
  # declared here so readers have ONE place to look up context shape.
  # validate! is called at Intake boundary to catch wrong callers early.
  module PipelineContext
    # Keys guaranteed present after Intake
    INTAKE_KEYS = %i[user_message on_chunk].freeze
    # Keys added by Intake
    INTAKE_OUT  = %i[intent].freeze
    # Keys added by Route
    ROUTE_KEYS  = %i[model].freeze
    # Keys added by Execute
    EXECUTE_KEYS = %i[output tool_calls].freeze

    module_function

    def validate!(ctx)
      missing = INTAKE_KEYS.reject { |k| ctx.key?(k) }
      return if missing.empty?
      raise ArgumentError, "PipelineContext missing required keys: #{missing.join(', ')}"
    end

    def build(user_message:, **opts)
      { user_message:, on_chunk: opts[:on_chunk] }.merge(opts)
    end
  end
  end
end
