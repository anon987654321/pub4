# frozen_string_literal: true

require "yaml"
require_relative "model_catalogue_sections_guard"

module Master
  # Local integrity checks for model identities, tier membership, routes and
  # failover policy. External provider availability remains a separate probe.
  module ModelCatalogueGuard
    module_function

    MODEL_TOP_LEVEL_FIELDS = %w[
      schema routing weights fallback_policy failover defaults model_defs models routes
      task_strengths vision_families tool_capable_prefixes operation_constraints continuity
      openrouter ferrum_web_chat three_mirror_redundancy subscription_lanes cli_lanes
      local_servers openai_compatible replicate_chat ollama free_tier paid_tail media_lanes
    ].freeze
    MODEL_MAP_SECTIONS = %w[
      routing weights fallback_policy failover defaults model_defs models routes task_strengths
      vision_families operation_constraints continuity openrouter ferrum_web_chat
      three_mirror_redundancy cli_lanes openai_compatible ollama free_tier paid_tail media_lanes
    ].freeze
    MODEL_ARRAY_SECTIONS = %w[tool_capable_prefixes subscription_lanes local_servers replicate_chat].freeze
    MODEL_SCORE_FIELDS = %w[quality speed cost].freeze
    def validate(data, path:)
      errors = []
      errors << "models.yml schema must be 1" unless data["schema"] == 1
      unknown = data.keys.map(&:to_s) - MODEL_TOP_LEVEL_FIELDS
      errors << "models.yml has unknown top-level field(s): #{unknown.sort.join(', ')}" unless unknown.empty?

      MODEL_MAP_SECTIONS.each do |section|
        errors << "models.yml #{section} must be a mapping" unless data[section].is_a?(Hash)
      end
      MODEL_ARRAY_SECTIONS.each do |section|
        values = data[section]
        unless values.is_a?(Array) && values.all? { |value| value.is_a?(String) && !value.strip.empty? }
          errors << "models.yml #{section} must be a list of non-empty strings"
        end
      end

      routing = data["routing"].is_a?(Hash) ? data["routing"] : {}
      %w[enabled escalation_enabled].each do |field|
        errors << "models.yml routing.#{field} must be boolean" unless [true, false].include?(routing[field])
      end
      errors << "models.yml routing.strategy must be non-empty text" unless
        routing["strategy"].is_a?(String) && !routing["strategy"].strip.empty?
      errors << "models.yml routing.provider must be non-empty text" unless
        routing["provider"].is_a?(String) && !routing["provider"].strip.empty?

      providers_path = File.join(File.dirname(path), "providers.yml")
      if File.file?(providers_path)
        provider_data = YAML.safe_load_file(providers_path, aliases: true)
        if provider_data.is_a?(Hash) && !provider_data.key?(routing["provider"])
          errors << "models.yml routing.provider #{routing["provider"].inspect} is absent from providers.yml"
        end
      end

      weights = data["weights"].is_a?(Hash) ? data["weights"] : {}
      validate_scores(weights, "models.yml weights", errors)

      defaults = data["defaults"].is_a?(Hash) ? data["defaults"] : {}
      validate_scores(defaults["score"], "models.yml defaults.score", errors)

      fallback = data["fallback_policy"].is_a?(Hash) ? data["fallback_policy"] : {}
      fallback_on = fallback["on"]
      unless fallback_on.is_a?(Array) && !fallback_on.empty? &&
             fallback_on.all? { |value| value.is_a?(String) && !value.strip.empty? }
        errors << 'models.yml fallback_policy must declare "on" as a non-empty list of error categories'
      end
      errors << "models.yml fallback_policy has unknown field(s)" unless (fallback.keys.map(&:to_s) - ["on"]).empty?

      failover = data["failover"].is_a?(Hash) ? data["failover"] : {}
      sequence = failover["sequence"]
      tiers = data["models"].is_a?(Hash) ? data["models"] : {}
      unless sequence.is_a?(Array) && !sequence.empty? && sequence.all? { |tier| tiers.key?(tier) }
        errors << "models.yml failover.sequence must reference declared model tiers"
      end
      %w[cooldown_seconds skip_ttl_ms transient_skip_ttl_ms].each do |field|
        value = failover[field]
        errors << "models.yml failover.#{field} must be positive" unless value.is_a?(Numeric) && value.positive?
      end
      cooldown_tiers = failover["cooldown_tiers"]
      unless cooldown_tiers.is_a?(Array) && !cooldown_tiers.empty? &&
             cooldown_tiers.all? { |value| value.is_a?(Numeric) && value.positive? }
        errors << "models.yml failover.cooldown_tiers must be a list of positive durations"
      end
      retries = failover["max_retries"]
      errors << "models.yml failover.max_retries must be a non-negative integer" unless retries.is_a?(Integer) && retries >= 0

      definitions = data["model_defs"].is_a?(Hash) ? data["model_defs"] : {}
      definition_ids = {}
      definitions.each do |name, row|
        unless name.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
          errors << "models.yml has invalid model definition name #{name.inspect}"
        end
        unless row.is_a?(Hash)
          errors << "model_defs.#{name} must be a mapping"
          next
        end
        id = row["id"]
        unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9][A-Za-z0-9._:\/+-]*\z/)
          errors << "model_defs.#{name}.id must be a valid model identifier"
        end
        if id.is_a?(String)
          errors << "model_defs contains duplicate model id #{id}" if definition_ids.key?(id)
          definition_ids[id] = name
        end
        validate_scores(row["score"], "model_defs.#{name}.score", errors)
        if row.key?("context_window")
          window = row["context_window"]
          errors << "model_defs.#{name}.context_window must be a positive integer" unless window.is_a?(Integer) && window.positive?
        end
        extras = row.keys.map(&:to_s) - %w[id score context_window]
        errors << "model_defs.#{name} has unknown field(s): #{extras.sort.join(', ')}" unless extras.empty?
      end
      errors << "models.yml model_defs must be a non-empty mapping" if definitions.empty?

      if data["models"].is_a?(Hash)
        tiers.each do |tier, rows|
          unless tier.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
            errors << "models.yml has invalid model tier #{tier.inspect}"
          end
          unless rows.is_a?(Array) && !rows.empty?
            errors << "models.#{tier} must be a non-empty list"
            next
          end
          rows.each_with_index do |row, index|
            unless row.is_a?(Hash)
              errors << "models.#{tier}[#{index}] must be a mapping"
              next
            end
            unknown_fields = row.keys.map(&:to_s) - %w[id score context_window]
            errors << "models.#{tier}[#{index}] has unknown field(s): #{unknown_fields.sort.join(', ')}" unless unknown_fields.empty?
            id = row["id"]
            unless id.is_a?(String) && definition_ids.key?(id)
              errors << "models.#{tier}[#{index}] references unknown model id #{id.inspect}"
            end
            validate_scores(row["score"], "models.#{tier}[#{index}].score", errors)
            if row.key?("context_window")
              window = row["context_window"]
              errors << "models.#{tier}[#{index}].context_window must be a positive integer" unless window.is_a?(Integer) && window.positive?
            end
          end
        end
      end

      routes = data["routes"].is_a?(Hash) ? data["routes"] : {}
      routes.each do |operation, tier|
        errors << "models.yml route #{operation} must reference a declared model tier" unless
          tier.is_a?(String) && tiers.key?(tier)
      end

      task_strengths = data["task_strengths"].is_a?(Hash) ? data["task_strengths"] : {}
      task_strengths.each do |task, strengths|
        unless strengths.is_a?(Array) && strengths.all? { |value| value.is_a?(String) && !value.strip.empty? }
          errors << "models.yml task_strengths.#{task} must be a list of non-empty strings"
        end
      end

      vision = data["vision_families"].is_a?(Hash) ? data["vision_families"] : {}
      %w[reads_images blind].each do |field|
        patterns = vision[field]
        unless patterns.is_a?(Array) && !patterns.empty? && patterns.all? { |value| value.is_a?(String) && !value.empty? }
          errors << "models.yml vision_families.#{field} must be a list of regex strings"
          next
        end
        patterns.each do |pattern|
          begin
            Regexp.new(pattern)
          rescue RegexpError => error
            errors << "models.yml vision_families.#{field} has invalid regex: #{error.message}"
          end
        end
      end

      constraints = data["operation_constraints"].is_a?(Hash) ? data["operation_constraints"] : {}
      constraints.each do |operation, row|
        unless row.is_a?(Hash)
          errors << "models.yml operation_constraints.#{operation} must be a mapping"
          next
        end
        unknown_fields = row.keys.map(&:to_s) - %w[min_quality preferred_tier]
        errors << "models.yml operation_constraints.#{operation} has unknown field(s): #{unknown_fields.sort.join(', ')}" unless unknown_fields.empty?
        quality = row["min_quality"]
        unless quality.is_a?(Numeric) && quality >= 0 && quality <= 1
          errors << "models.yml operation_constraints.#{operation}.min_quality must be between 0 and 1"
        end
        errors << "models.yml operation_constraints.#{operation}.preferred_tier is unknown" unless
          row["preferred_tier"].is_a?(String) && tiers.key?(row["preferred_tier"])
      end

      ModelCatalogueSectionsGuard.validate(data, tiers:, errors:)

      errors << "models.yml tool_capable_prefixes must not be empty" if Array(data["tool_capable_prefixes"]).empty?
      errors << "models.yml subscription_lanes must not be empty" if Array(data["subscription_lanes"]).empty?
      errors << "models.yml replicate_chat must not be empty" if Array(data["replicate_chat"]).empty?

      raise ArgumentError, errors.uniq.join("; ") unless errors.empty?
      true
    end

    def validate_scores(score, label, errors)
      unless score.is_a?(Hash)
        errors << "#{label} must be a mapping"
        return
      end
      missing = MODEL_SCORE_FIELDS - score.keys.map(&:to_s)
      errors << "#{label} is missing #{missing.join(', ')}" unless missing.empty?
      unknown = score.keys.map(&:to_s) - MODEL_SCORE_FIELDS
      errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
      MODEL_SCORE_FIELDS.each do |field|
        value = score[field]
        errors << "#{label}.#{field} must be between 0 and 1" unless value.is_a?(Numeric) && value >= 0 && value <= 1
      end
    end


  end
end
