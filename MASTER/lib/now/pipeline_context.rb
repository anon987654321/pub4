# frozen_string_literal: true

module Master
  module Now
  # PipelineContext — canonical key inventory for the pipeline Hash.
  # All keys flowing through the pipeline are declared here.
  # validate! is called at the Intake boundary to catch wrong callers early.
  # fetch! is the safe read — raises KeyError on missing keys, never returns nil.
  module PipelineContext
    # Required on entry — validate! enforces this
    INTAKE_REQUIRED = %i[user_message].freeze

    # Keys set by each stage (all optional after Intake)
    STAGE_KEYS = {
      intake:   %i[intent command args message],
      infer:    %i[task_type pressure original_message],
      route:    %i[handler model last_tool_tier],
      execute:  %i[output tool_calls written_files source],
      council:  %i[council_feedback],
      lint:     %i[lint_report lint_error],
      review:   %i[review_error],
      enhance:  %i[pre_enhanced],
      render:   %i[rendered voice],
      memory:   []
    }.freeze

    ALL_KEYS = (INTAKE_REQUIRED + STAGE_KEYS.values.flatten).uniq.freeze

    module_function

    def validate!(ctx)
      missing = INTAKE_REQUIRED.reject { |k| ctx.key?(k) }
      return if missing.empty?
      raise ArgumentError, "PipelineContext missing required keys: #{missing.join(', ')}"
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
