# frozen_string_literal: true

require "yaml"
require_relative "law_vocabulary"

module Master
  # Validates the governing YAML by its invariants. Who may write it is a
  # separate question soul.yml's sacred_paths answer: no automated writer may,
  # and a person commits it with ordinary git. These invariants judge every
  # candidate either way, so a write that is let through is still a valid one.
  module ConfigurationGuard
    module_function

    LAW_MODALITIES = LawVocabulary::MODALITIES

    REQUIRED_LAW_SECTIONS = %w[
      CAPABILITY_STATUS_MUST_BE_TRUTHFUL ROBUSTNESS SINGULARITY LINEARITY
      PROXIMITY ABSTRACTION DENSITY RENDERED_VALUES INTER_MODEL_CONTRACT
      veto_patterns law_map transformation_policy law_catalogue
    ].freeze
    # Sacred means no automated writer may change the path. The whole data/
    # directory cannot be: tokens, state and ratchet ceilings there are written
    # by the runtime every day. Nor can the retired scanner directories, which
    # would freeze scanner code that must evolve.
    TOO_BROAD_SACRED_PATHS = %w[
      data/ data lib/review/scan/ lib/review/scan/laws lib/review/scan/laws/
    ].freeze
    LIVE_SOUL = File.expand_path("../data/soul.yml", __dir__)
    PROVIDER_FIELDS = %w[
      env command strengths default_model model_pattern ruby_llm_key min_key_length
    ].freeze
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

    def validate(path:, content:, root: nil)
      absolute = File.expand_path(path.to_s, root || Dir.pwd)
      kind = kind_for(absolute)
      return unless kind

      data = YAML.safe_load(content, aliases: true)
      raise ArgumentError, "top-level YAML value must be a mapping" unless data.is_a?(Hash)

      case kind
      when :laws then validate_laws(data, path: absolute, text: content)
      when :soul then validate_soul(data, path: absolute)
      when :providers then validate_providers(data)
      when :models then validate_models(data, path: absolute)
      end
      nil
    rescue Psych::Exception, ArgumentError, KeyError, TypeError => e
      "configuration invariant failed: #{e.class}: #{e.message}"
    end

    def kind_for(path)
      normalized = File.expand_path(path.to_s).tr("\\", "/")
      return :laws if normalized.match?(%r{/MASTER/data/laws\.yml\z})
      return :soul if normalized.match?(%r{/MASTER/data/soul\.yml\z})
      return :providers if normalized.match?(%r{/MASTER/data/providers\.yml\z})
      return :models if normalized.match?(%r{/MASTER/data/models\.yml\z})

      nil
    end


    # Provider and model configuration is both runtime policy and a catalogue
    # of executable routes. YAML validity alone cannot detect an unknown route,
    # an invalid provider field or a model row that its own tier never declares.
    def validate_providers(data)
      errors = []
      errors << "providers.yml schema must be 1" unless data["schema"] == 1
      providers = data.reject { |name, _row| name.to_s == "schema" }
      errors << "providers.yml must contain provider mappings" if providers.empty?

      providers.each do |name, row|
        unless name.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
          errors << "providers.yml has invalid provider name #{name.inspect}"
        end
        unless row.is_a?(Hash)
          errors << "provider #{name} must be a mapping"
          next
        end

        unknown = row.keys.map(&:to_s) - PROVIDER_FIELDS
        errors << "provider #{name} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?

        env = row["env"]
        unless env.is_a?(Array) && env.uniq == env &&
               env.all? { |value| value.is_a?(String) && value.match?(/\A[A-Z][A-Z0-9_]*\z/) }
          errors << "provider #{name}.env must be a unique list of environment-variable names"
        end

        strengths = row["strengths"]
        unless strengths.is_a?(Array) && !strengths.empty? &&
               strengths.all? { |value| value.is_a?(String) && value.match?(/\A[a-z][a-z0-9_]*\z/) }
          errors << "provider #{name}.strengths must be a non-empty list of capability names"
        end

        unless row["default_model"].is_a?(String) && !row["default_model"].strip.empty?
          errors << "provider #{name}.default_model must be non-empty text"
        end

        if row.key?("command") && !(row["command"].is_a?(String) && !row["command"].strip.empty?)
          errors << "provider #{name}.command must be non-empty text"
        end

        if row.key?("model_pattern")
          pattern = row["model_pattern"]
          if !pattern.is_a?(String) || pattern.empty?
            errors << "provider #{name}.model_pattern must be non-empty regex text"
          else
            begin
              Regexp.new(pattern)
            rescue RegexpError => error
              errors << "provider #{name}.model_pattern is invalid: #{error.message}"
            end
          end
        end

        key = row["ruby_llm_key"]
        minimum = row["min_key_length"]
        if key.nil? != minimum.nil?
          errors << "provider #{name} must declare ruby_llm_key and min_key_length together"
        end
        unless key.nil?
          errors << "provider #{name}.ruby_llm_key must be a snake_case key name" unless
            key.is_a?(String) && key.match?(/\A[a-z][a-z0-9_]*\z/)
          errors << "provider #{name} needs at least one key environment variable" unless
            env.is_a?(Array) && !env.empty?
          errors << "provider #{name}.min_key_length must be a positive integer" unless
            minimum.is_a?(Integer) && minimum.positive?
        end
      end

      raise ArgumentError, errors.uniq.join("; ") unless errors.empty?
      true
    end

    def validate_models(data, path:)
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
            id = row["id"]
            unless id.is_a?(String) && definition_ids.key?(id)
              errors << "models.#{tier}[#{index}] references unknown model id #{id.inspect}"
            end
            validate_scores(row["score"], "models.#{tier}[#{index}].score", errors)
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
        quality = row["min_quality"]
        unless quality.is_a?(Numeric) && quality >= 0 && quality <= 1
          errors << "models.yml operation_constraints.#{operation}.min_quality must be between 0 and 1"
        end
        errors << "models.yml operation_constraints.#{operation}.preferred_tier is unknown" unless
          row["preferred_tier"].is_a?(String) && tiers.key?(row["preferred_tier"])
      end

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


    def validate_soul(data, path: LIVE_SOUL)
      absolute = data.fetch("absolute") { raise KeyError, "absolute section is required" }
      raise ArgumentError, "absolute section must be a mapping" unless absolute.is_a?(Hash)
      unless absolute["golden_law"] == "PRESERVE_THEN_IMPROVE_NEVER_BREAK"
        raise ArgumentError, "golden_law must remain PRESERVE_THEN_IMPROVE_NEVER_BREAK"
      end

      validate_sacred_paths(Array(absolute["sacred_paths"]).map { |entry| normalize_path(entry) }, path)
    end

    def validate_sacred_paths(paths, path)
      raise ArgumentError, "sacred_paths must not be empty" if paths.empty?

      broad = paths.select { |entry| TOO_BROAD_SACRED_PATHS.include?(entry) }
      unless broad.empty?
        raise ArgumentError, "runtime-written data and retired scanner paths cannot be sacred: #{broad.join(', ')}"
      end

      missing = live_sacred_paths(path) - paths
      raise ArgumentError, "critical path protections missing: #{missing.join(', ')}" unless missing.empty?
    end

    # soul.yml is the one list. A candidate keeps every path the soul it replaces
    # declares, so no validated write can drop a protection; a person removes one
    # with an ordinary commit. A candidate for a file not yet written is held to
    # this MASTER's soul.
    def live_sacred_paths(path)
      soul = YAML.safe_load_file(File.file?(path) ? path : LIVE_SOUL, aliases: true)
      declared = soul.is_a?(Hash) && soul["absolute"].is_a?(Hash) ? soul["absolute"]["sacred_paths"] : nil

      Array(declared).map { |entry| normalize_path(entry) }
    end

    def validate_laws(data, path:, text:)
      validate_required_law_sections(data)
      catalogue = data.fetch("law_catalogue")
      validate_catalogue_contract(catalogue)
      entries = catalogue.fetch("entries")
      validate_catalogue_entries(entries, repository_root(path))
      validate_catalogue_key_duplicates(text, entries.keys)
    end

    def validate_required_law_sections(data)
      missing = REQUIRED_LAW_SECTIONS - data.keys.map(&:to_s)
      raise ArgumentError, "required Law sections missing: #{missing.join(', ')}" unless missing.empty?
    end

    def validate_catalogue_contract(catalogue)
      raise ArgumentError, "law_catalogue must be a mapping" unless catalogue.is_a?(Hash)
      modalities = Array(catalogue["modalities"]).map(&:to_s).uniq.sort
      raise ArgumentError, "law_catalogue.modalities must be #{LAW_MODALITIES.join(', ')}" unless modalities == LAW_MODALITIES
      raise ArgumentError, "law_catalogue.surfaces must be non-empty" if Array(catalogue["surfaces"]).empty?
      entries = catalogue.fetch("entries") { raise KeyError, "law_catalogue.entries is required" }
      raise ArgumentError, "law_catalogue.entries must be a non-empty mapping" unless entries.is_a?(Hash) && !entries.empty?

      keys = entries.keys.map { |id| id.to_s.downcase }
      duplicates = keys.tally.select { |_id, count| count > 1 }.keys
      raise ArgumentError, "duplicate Law identities: #{duplicates.join(', ')}" unless duplicates.empty?
    end

    def validate_catalogue_entries(entries, repo_root)
      entries.each do |id, row|
        raise ArgumentError, "Law #{id} must be a mapping" unless row.is_a?(Hash)
        raise ArgumentError, "Law #{id} must be universal" unless row["universal"] == true
        modalities = Array(row["modalities"]).map(&:to_s).uniq.sort
        raise ArgumentError, "Law #{id} modalities must be #{LAW_MODALITIES.join(', ')}" unless modalities == LAW_MODALITIES

        validate_catalogue_sources(id, row)
      end
    end

    def validate_catalogue_sources(id, row)
      sources = (Array(row["definition_sources"]) + Array(row["detector_sources"])).map(&:to_s).uniq
      raise ArgumentError, "Law #{id} must name a Ruby source" if sources.empty?
      sources.each { |source| validate_catalogue_source(id, source) }
    end

    # Path syntax belongs in per-write admission. File existence belongs in the
    # whole-tree LawRegistryAudit, because one transaction may add/move the file
    # and update the catalogue in either write order.
    def validate_catalogue_source(id, source)
      valid = source.start_with?("MASTER/law/") && source.end_with?(".rb") &&
              !source.split("/").include?("..")
      raise ArgumentError, "Law #{id} has invalid source path #{source.inspect}" unless valid
    end

    def validate_catalogue_key_duplicates(text, ids)
      catalogue_start = text.index(/^law_catalogue:\s*$/)
      entries_start = text.index(/^  entries:\s*$/, catalogue_start || 0)
      raise ArgumentError, "law_catalogue.entries source section is missing" unless catalogue_start && entries_start

      declared = text[entries_start..].lines.filter_map do |line|
        match = line.match(/\A    ([A-Za-z0-9_]+):\s*\z/)
        match && match[1].downcase
      end
      expected = ids.map { |id| id.to_s.downcase }.sort
      raise ArgumentError, "Law catalogue keys are duplicated or malformed in YAML source" unless declared.sort == expected
    end

    def normalize_path(value)
      path = value.to_s.tr("\\", "/").strip
      raise ArgumentError, "sacred path must be non-empty" if path.empty?
      raise ArgumentError, "sacred path must be relative: #{path}" if path.start_with?("/") || path.match?(/\A[A-Za-z]:/)
      raise ArgumentError, "sacred path escapes its root: #{path}" if path.split("/").include?("..")

      path
    end

    def repository_root(path)
      master_root = File.dirname(File.dirname(File.expand_path(path)))
      File.dirname(master_root)
    end
  end
end
