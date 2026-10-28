# frozen_string_literal: true

module Master
  # Runtime-critical budgets and mode selectors must validate before any consumer
  # can silently substitute its local default. The unread guidance subtree remains prose.
  module LimitsCatalogueGuard
    module_function

    SECTION_NAMES = %w[
      law_groups scan_profiles scan_workers autoloop zeitwerk dmesg session_modes
      guidance loc_body_budgets convergence_discipline fix_budget fix_time process
      orientation governor
    ].freeze
    ROOT_FIELDS = (["schema"] + SECTION_NAMES).freeze
    SCAN_PROFILE_FIELDS = %w[laws aliases description severity].freeze
    SESSION_MODE_FIELDS = %w[
      scan_profile council autofix_llm autofix_mechanical semantic_sample
      max_fix_passes description severity_floor
    ].freeze
    TIME_FIELDS = %w[file_s run_s stall_s].freeze

    def validate(data)
      errors = []
      unknown = data.keys.map(&:to_s) - ROOT_FIELDS
      errors << "limits.yml has unknown top-level field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
      errors << "limits.yml schema must be 1" unless data["schema"] == 1
      missing = ROOT_FIELDS - data.keys.map(&:to_s)
      errors << "limits.yml is missing required section(s): #{missing.join(', ')}" unless missing.empty?

      SECTION_NAMES.each do |section|
        next if section == "scan_workers"

        errors << "limits.yml #{section} must be a mapping" unless data[section].is_a?(Hash)
      end
      errors << "limits.yml scan_workers must be a positive integer" unless
        data["scan_workers"].is_a?(Integer) && data["scan_workers"].positive?

      validate_law_groups(data["law_groups"], errors)
      validate_scan_profiles(data["scan_profiles"], errors)
      validate_autoloop(data["autoloop"], errors)
      validate_zeitwerk(data["zeitwerk"], errors)
      validate_dmesg(data["dmesg"], errors)
      validate_session_modes(data["session_modes"], data["scan_profiles"], errors)
      validate_positive_mapping(data["loc_body_budgets"], "limits.yml loc_body_budgets", errors)
      validate_positive_mapping(data["convergence_discipline"], "limits.yml convergence_discipline", errors)
      validate_fix_budget(data["fix_budget"], errors)
      validate_fix_time(data["fix_time"], errors)
      validate_process(data["process"], errors)
      validate_orientation(data["orientation"], errors)
      validate_governor(data["governor"], errors)

      raise ArgumentError, errors.uniq.join("; ") unless errors.empty?
      true
    end

    def validate_law_groups(value, errors)
      return unless value.is_a?(Hash)

      value.each do |name, members|
        unless members.is_a?(Array) && !members.empty? &&
               members.all? { |member| member.is_a?(String) && !member.strip.empty? }
          errors << "limits.yml law_groups.#{name} must be a non-empty list of names"
        end
      end
    end

    def validate_scan_profiles(value, errors)
      return unless value.is_a?(Hash)

      default = value["default"]
      profiles = value.reject { |key, _entry| key.to_s == "default" }
      unless default.is_a?(String) && profiles.key?(default)
        errors << "limits.yml scan_profiles.default must name a declared profile"
      end

      profiles.each do |name, row|
        unless row.is_a?(Hash)
          errors << "limits.yml scan_profiles.#{name} must be a mapping"
          next
        end
        unknown = row.keys.map(&:to_s) - SCAN_PROFILE_FIELDS
        errors << "limits.yml scan_profiles.#{name} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
        errors << "limits.yml scan_profiles.#{name}.laws must be non-empty text" unless
          row["laws"].is_a?(String) && !row["laws"].strip.empty?
        errors << "limits.yml scan_profiles.#{name}.description must be non-empty text" unless
          row["description"].is_a?(String) && !row["description"].strip.empty?
        if row.key?("aliases")
          aliases = row["aliases"]
          unless aliases.is_a?(Array) && aliases.uniq == aliases &&
                 aliases.all? { |alias_name| alias_name.is_a?(String) && !alias_name.strip.empty? }
            errors << "limits.yml scan_profiles.#{name}.aliases must be a unique list of names"
          end
        end
        if row.key?("severity")
          severity = row["severity"]
          unless severity.is_a?(Array) && !severity.empty? &&
                 severity.all? { |level| %w[info warning error critical veto].include?(level.to_s) }
            errors << "limits.yml scan_profiles.#{name}.severity must be a non-empty list of severity names"
          end
        end
      end
    end

    def validate_autoloop(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[scan_file_sleep_s poll_interval], "limits.yml autoloop", errors)
      %w[scan_file_sleep_s poll_interval].each do |field|
        minimum = field == "scan_file_sleep_s" ? 0 : 1
        number = value[field]
        errors << "limits.yml autoloop.#{field} must be numeric and >= #{minimum}" unless
          number.is_a?(Numeric) && number >= minimum
      end
    end

    def validate_zeitwerk(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, ["inflections"], "limits.yml zeitwerk", errors)
      inflections = value["inflections"]
      unless inflections.is_a?(Hash) && !inflections.empty? &&
             inflections.all? { |key, constant| key.to_s.match?(/\A[a-z][a-z0-9_]*\z/) &&
               constant.is_a?(String) && constant.match?(/\A[A-Z][A-Za-z0-9]*\z/) }
        errors << "limits.yml zeitwerk.inflections must map snake_case names to constant names"
      end
    end

    def validate_dmesg(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[enabled verbosity style format env through scan_progress milestones flush],
                  "limits.yml dmesg", errors)
      errors << "limits.yml dmesg.enabled must be boolean" unless [true, false].include?(value["enabled"])
      %w[verbosity style format env].each do |field|
        errors << "limits.yml dmesg.#{field} must be non-empty text" unless
          value[field].is_a?(String) && !value[field].strip.empty?
      end
      %w[through scan_progress milestones flush].each do |field|
        errors << "limits.yml dmesg.#{field} must be boolean" unless [true, false].include?(value[field])
      end
    end

    def validate_session_modes(value, profiles, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[default env modes], "limits.yml session_modes", errors)
      modes = value["modes"]
      unless modes.is_a?(Hash) && !modes.empty?
        errors << "limits.yml session_modes.modes must be a non-empty mapping"
        return
      end
      unless value["default"].is_a?(String) && modes.key?(value["default"])
        errors << "limits.yml session_modes.default must name a declared mode"
      end
      errors << "limits.yml session_modes.env must be non-empty text" unless
        value["env"].is_a?(String) && !value["env"].strip.empty?

      profile_names = profiles.is_a?(Hash) ? profiles.keys.map(&:to_s) - ["default"] : []
      modes.each do |name, row|
        unless row.is_a?(Hash)
          errors << "limits.yml session_modes.modes.#{name} must be a mapping"
          next
        end
        unknown = row.keys.map(&:to_s) - SESSION_MODE_FIELDS
        errors << "limits.yml session_modes.modes.#{name} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
        errors << "limits.yml session_modes.modes.#{name}.scan_profile must reference a declared profile" unless
          row["scan_profile"].is_a?(String) && profile_names.include?(row["scan_profile"])
        %w[autofix_llm autofix_mechanical].each do |field|
          errors << "limits.yml session_modes.modes.#{name}.#{field} must be boolean" unless
            [true, false].include?(row[field])
        end
        unless [true, false, "risky"].include?(row["council"])
          errors << "limits.yml session_modes.modes.#{name}.council must be true, false or risky"
        end
        sample = row["semantic_sample"]
        errors << "limits.yml session_modes.modes.#{name}.semantic_sample must be between 0 and 1" unless
          sample.is_a?(Numeric) && sample >= 0 && sample <= 1
        passes = row["max_fix_passes"]
        errors << "limits.yml session_modes.modes.#{name}.max_fix_passes must be a positive integer" unless
          passes.is_a?(Integer) && passes.positive?
        errors << "limits.yml session_modes.modes.#{name}.description must be non-empty text" unless
          row["description"].is_a?(String) && !row["description"].strip.empty?
        if row.key?("severity_floor")
          errors << "limits.yml session_modes.modes.#{name}.severity_floor must be a severity name" unless
            %w[info warning error critical veto].include?(row["severity_floor"].to_s)
        end
      end
    end

    def validate_positive_mapping(value, label, errors)
      return unless value.is_a?(Hash)

      errors << "#{label} must not be empty" if value.empty?
      value.each do |key, number|
        unless number.is_a?(Numeric) && number.positive?
          errors << "#{label}.#{key} must be positive"
        end
      end
    end

    def validate_fix_budget(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[law_share run_tokens law_shares], "limits.yml fix_budget", errors)
      share = value["law_share"]
      errors << "limits.yml fix_budget.law_share must be between 0 and 1" unless
        share.is_a?(Numeric) && share.positive? && share <= 1
      tokens = value["run_tokens"]
      errors << "limits.yml fix_budget.run_tokens must be a positive integer" unless
        tokens.is_a?(Integer) && tokens.positive?
      shares = value["law_shares"]
      unless shares.is_a?(Hash) && shares.all? { |_id, fraction| fraction.is_a?(Numeric) && fraction.positive? && fraction <= 1 }
        errors << "limits.yml fix_budget.law_shares must map Law IDs to fractions in (0, 1]"
      end
    end

    def validate_fix_time(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[default lanes], "limits.yml fix_time", errors)
      validate_time_row(value["default"], "limits.yml fix_time.default", errors)
      lanes = value["lanes"]
      unless lanes.is_a?(Hash) && !lanes.empty?
        errors << "limits.yml fix_time.lanes must be a non-empty mapping"
        return
      end
      lanes.each { |name, row| validate_time_row(row, "limits.yml fix_time.lanes.#{name}", errors) }
    end

    def validate_time_row(value, label, errors)
      unless value.is_a?(Hash)
        errors << "#{label} must be a mapping"
        return
      end
      strict_keys(value, TIME_FIELDS, label, errors)
      TIME_FIELDS.each do |field|
        number = value[field]
        errors << "#{label}.#{field} must be a positive number of seconds" unless
          number.is_a?(Numeric) && number.positive?
      end
    end

    def validate_process(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[defaults loops load resources], "limits.yml process", errors)
      defaults = value["defaults"]
      unless defaults.is_a?(Hash)
        errors << "limits.yml process.defaults must be a mapping"
      else
        errors << "limits.yml process.defaults.safe_mode must be boolean" unless [true, false].include?(defaults["safe_mode"])
        %w[max_active_loops loop_cooldown_seconds].each do |field|
          number = defaults[field]
          errors << "limits.yml process.defaults.#{field} must be non-negative numeric" unless
            number.is_a?(Numeric) && number >= 0
        end
      end
      loops = value["loops"]
      unless loops.is_a?(Hash) && !loops.empty?
        errors << "limits.yml process.loops must be a non-empty mapping"
      else
        loops.each do |name, row|
          unless row.is_a?(Hash)
            errors << "limits.yml process.loops.#{name} must be a mapping"
            next
          end
          errors << "limits.yml process.loops.#{name}.env must be an environment variable name" unless
            row["env"].is_a?(String) && row["env"].match?(/\A[A-Z][A-Z0-9_]*\z/)
          %w[max_run_seconds min_sleep_seconds].each do |field|
            number = row[field]
            errors << "limits.yml process.loops.#{name}.#{field} must be non-negative numeric" unless
              number.is_a?(Numeric) && number >= 0
          end
        end
      end
      %w[load resources].each do |section|
        mapping = value[section]
        unless mapping.is_a?(Hash) && !mapping.empty?
          errors << "limits.yml process.#{section} must be a non-empty mapping"
          next
        end
        mapping.each do |name, thresholds|
          if section == "resources" && thresholds.is_a?(Hash) && thresholds.keys.any? { |key| key == "darwin" }
            thresholds = thresholds.reject { |key, _entry| key == "darwin" }.merge("darwin" => thresholds["darwin"])
            thresholds.each do |platform, row|
              validate_threshold_row(row, "limits.yml process.resources.#{name}.#{platform}", errors)
            end
          else
            validate_threshold_row(thresholds, "limits.yml process.#{section}.#{name}", errors)
          end
        end
      end
    end

    def validate_threshold_row(value, label, errors)
      unless value.is_a?(Hash)
        errors << "#{label} must be a mapping"
        return
      end
      unknown = value.keys.map(&:to_s) - %w[warn crit]
      errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
      %w[warn crit].each do |field|
        number = value[field]
        errors << "#{label}.#{field} must be positive numeric" unless number.is_a?(Numeric) && number.positive?
      end
    end

    def validate_orientation(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[tree tree_max_bytes read_in_full], "limits.yml orientation", errors)
      errors << "limits.yml orientation.tree must be non-empty text" unless value["tree"].is_a?(String) && !value["tree"].empty?
      errors << "limits.yml orientation.tree_max_bytes must be a positive integer" unless
        value["tree_max_bytes"].is_a?(Integer) && value["tree_max_bytes"].positive?
      errors << "limits.yml orientation.read_in_full must be non-empty text" unless
        value["read_in_full"].is_a?(String) && !value["read_in_full"].strip.empty?
    end

    def validate_governor(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, ["rate_limits"], "limits.yml governor", errors)
      limits = value["rate_limits"]
      unless limits.is_a?(Hash) && !limits.empty? &&
             limits.all? { |tier, amount| tier.is_a?(String) && amount.is_a?(Numeric) && amount.positive? }
        errors << "limits.yml governor.rate_limits must map tiers to positive numeric limits"
      end
    end

    def strict_keys(value, allowed, label, errors)
      unknown = value.keys.map(&:to_s) - allowed
      errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
    end
  end
end
