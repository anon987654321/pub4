# frozen_string_literal: true

module Master
  # Runtime-critical budgets and mode selectors must validate before any consumer
  # can silently substitute its local default. Each of console.yml, scan.yml and
  # budgets.yml holds exactly the sections Master::CONFIG_FILES gives it.
  module ConfigSectionsGuard
    module_function

    SCAN_PROFILE_FIELDS = %w[laws aliases description severity].freeze
    SESSION_MODE_FIELDS = %w[
      scan_profile council autofix_llm autofix_mechanical semantic_sample
      max_fix_passes description severity_floor
    ].freeze
    TIME_FIELDS = %w[file_s run_s stall_s].freeze

    # Section => its validator and the sections it checks references against.
    # Each validator returns at once when its section is absent, so one table
    # serves all three files.
    VALIDATORS = {
      "law_groups" => [:validate_law_groups], "scan_profiles" => [:validate_scan_profiles, "law_groups"],
      "session_modes" => [:validate_session_modes, "scan_profiles"], "autoloop" => [:validate_autoloop],
      "dmesg" => [:validate_dmesg], "convergence_discipline" => [:validate_convergence_discipline],
      "fix_budget" => [:validate_fix_budget], "fix_time" => [:validate_fix_time], "process" => [:validate_process],
      "orientation" => [:validate_orientation], "governor" => [:validate_governor],
    }.freeze

    def sections_of(file) = Master::CONFIG_FILES.select { |_section, owner| owner == file }.keys

    def validate(data, path:)
      file = File.basename(path.to_s)
      errors = shape_errors(data, file)
      validate_scan_workers(data, errors)
      VALIDATORS.each { |section, (method, *refs)| send(method, data[section], *refs.map { |ref| data[ref] }, errors) }

      raise ArgumentError, errors.uniq.join("; ") unless errors.empty?

      true
    end

    def shape_errors(data, file)
      expected = sections_of(file)
      present = data.keys.map(&:to_s)
      not_mappings = (expected - %w[scan_workers]).reject { |section| data[section].is_a?(Hash) }
      unknown = present - expected
      missing = expected - present
      [
        ("#{file} has unknown top-level field(s): #{unknown.sort.join(', ')}" if unknown.any?),
        ("#{file} is missing required section(s): #{missing.join(', ')}" if missing.any?),
        *not_mappings.map { |section| "#{file} #{section} must be a mapping" },
      ].compact
    end

    def validate_scan_workers(data, errors)
      workers = data.fetch("scan_workers", 1)
      errors << "scan_workers must be a positive integer" unless workers.is_a?(Integer) && workers.positive?
    end

    def validate_convergence_discipline(value, errors)
      validate_positive_mapping(value, "convergence_discipline", errors)
    end

    def validate_law_groups(value, errors)
      return unless value.is_a?(Hash)

      value.each do |name, members|
        unless members.is_a?(Array) && !members.empty? &&
               members.all? { |member| member.is_a?(String) && !member.strip.empty? }
          errors << "law_groups.#{name} must be a non-empty list of names"
        end
      end
    end

    def validate_scan_profiles(value, law_groups, errors)
      return unless value.is_a?(Hash)

      default = value["default"]
      profiles = value.reject { |key, _entry| key.to_s == "default" }
      unless default.is_a?(String) && profiles.key?(default)
        errors << "scan_profiles.default must name a declared profile"
      end

      profiles.each do |name, row|
        unless row.is_a?(Hash)
          errors << "scan_profiles.#{name} must be a mapping"
          next
        end
        unknown = row.keys.map(&:to_s) - SCAN_PROFILE_FIELDS
        errors << "scan_profiles.#{name} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
        laws = row["laws"]
        errors << "scan_profiles.#{name}.laws must be non-empty text" unless
          laws.is_a?(String) && !laws.strip.empty?
        if laws.is_a?(String) && !laws.empty? && laws != "*" &&
           !(law_groups.is_a?(Hash) && law_groups.key?(laws))
          errors << "scan_profiles.#{name}.laws must be '*' or reference a declared law group"
        end
        errors << "scan_profiles.#{name}.description must be non-empty text" unless
          row["description"].is_a?(String) && !row["description"].strip.empty?
        if row.key?("aliases")
          aliases = row["aliases"]
          unless aliases.is_a?(Array) && aliases.uniq == aliases &&
                 aliases.all? { |alias_name| alias_name.is_a?(String) && !alias_name.strip.empty? }
            errors << "scan_profiles.#{name}.aliases must be a unique list of names"
          end
        end
        if row.key?("severity")
          severity = row["severity"]
          unless severity.is_a?(Array) && !severity.empty? &&
                 severity.all? { |level| %w[info warning error critical veto].include?(level.to_s) }
            errors << "scan_profiles.#{name}.severity must be a non-empty list of severity names"
          end
        end
      end
    end

    def validate_autoloop(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[scan_file_sleep_s poll_interval], "autoloop", errors)
      %w[scan_file_sleep_s poll_interval].each do |field|
        minimum = field == "scan_file_sleep_s" ? 0 : 1
        number = value[field]
        errors << "autoloop.#{field} must be numeric and >= #{minimum}" unless
          number.is_a?(Numeric) && number >= minimum
      end
    end

    def validate_dmesg(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[enabled verbosity style format env through scan_progress milestones flush boot_sgr],
                  "dmesg", errors)
      validate_boot_sgr(value["boot_sgr"], errors)
      %w[verbosity style format env].each do |field|
        errors << "dmesg.#{field} must be non-empty text" unless
          value[field].is_a?(String) && !value[field].strip.empty?
      end
      %w[enabled through scan_progress milestones flush].each do |field|
        errors << "dmesg.#{field} must be boolean" unless [true, false].include?(value[field])
      end
    end

    # An SGR parameter list, or empty for plain: anything else reaches the terminal as an escape.
    def validate_boot_sgr(sgr, errors)
      return if sgr.nil? || sgr.to_s.match?(/\A(?:\d+(?:;\d+)*)?\z/)

      errors << "dmesg.boot_sgr must be digits and semicolons"
    end

    def validate_session_modes(value, profiles, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[default env modes], "session_modes", errors)
      modes = value["modes"]
      unless modes.is_a?(Hash) && !modes.empty?
        errors << "session_modes.modes must be a non-empty mapping"
        return
      end
      unless value["default"].is_a?(String) && modes.key?(value["default"])
        errors << "session_modes.default must name a declared mode"
      end
      errors << "session_modes.env must be non-empty text" unless
        value["env"].is_a?(String) && !value["env"].strip.empty?

      profile_names = profiles.is_a?(Hash) ? profiles.keys.map(&:to_s) - ["default"] : []
      modes.each do |name, row|
        unless row.is_a?(Hash)
          errors << "session_modes.modes.#{name} must be a mapping"
          next
        end
        unknown = row.keys.map(&:to_s) - SESSION_MODE_FIELDS
        errors << "session_modes.modes.#{name} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
        errors << "session_modes.modes.#{name}.scan_profile must reference a declared profile" unless
          row["scan_profile"].is_a?(String) && profile_names.include?(row["scan_profile"])
        %w[autofix_llm autofix_mechanical].each do |field|
          errors << "session_modes.modes.#{name}.#{field} must be boolean" unless
            [true, false].include?(row[field])
        end
        unless [true, false, "risky"].include?(row["council"])
          errors << "session_modes.modes.#{name}.council must be true, false or risky"
        end
        sample = row["semantic_sample"]
        errors << "session_modes.modes.#{name}.semantic_sample must be between 0 and 1" unless
          sample.is_a?(Numeric) && sample >= 0 && sample <= 1
        passes = row["max_fix_passes"]
        errors << "session_modes.modes.#{name}.max_fix_passes must be a positive integer" unless
          passes.is_a?(Integer) && passes.positive?
        errors << "session_modes.modes.#{name}.description must be non-empty text" unless
          row["description"].is_a?(String) && !row["description"].strip.empty?
        if row.key?("severity_floor")
          errors << "session_modes.modes.#{name}.severity_floor must be a severity name" unless
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

      strict_keys(value, %w[law_share run_tokens law_shares], "fix_budget", errors)
      share = value["law_share"]
      errors << "fix_budget.law_share must be between 0 and 1" unless
        share.is_a?(Numeric) && share.positive? && share <= 1
      tokens = value["run_tokens"]
      errors << "fix_budget.run_tokens must be a positive integer" unless
        tokens.is_a?(Integer) && tokens.positive?
      shares = value["law_shares"]
      shares_valid = shares.is_a?(Hash) && shares.all? do |id, fraction|
        id.to_s.match?(/\A[A-Za-z][A-Za-z0-9_]*\z/) && fraction.is_a?(Numeric) && fraction.positive? && fraction <= 1
      end
      errors << "fix_budget.law_shares must map valid Law IDs to fractions in (0, 1]" unless shares_valid
    end

    def validate_fix_time(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[default lanes], "fix_time", errors)
      validate_time_row(value["default"], "fix_time.default", errors)
      lanes = value["lanes"]
      unless lanes.is_a?(Hash) && !lanes.empty?
        errors << "fix_time.lanes must be a non-empty mapping"
        return
      end
      lanes.each { |name, row| validate_time_row(row, "fix_time.lanes.#{name}", errors) }
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

      strict_keys(value, %w[defaults loops load resources], "process", errors)
      defaults = value["defaults"]
      unless defaults.is_a?(Hash)
        errors << "process.defaults must be a mapping"
      else
        errors << "process.defaults.safe_mode must be boolean" unless [true, false].include?(defaults["safe_mode"])
        %w[max_active_loops loop_cooldown_seconds].each do |field|
          number = defaults[field]
          errors << "process.defaults.#{field} must be non-negative numeric" unless
            number.is_a?(Numeric) && number >= 0
        end
      end
      loops = value["loops"]
      unless loops.is_a?(Hash) && !loops.empty?
        errors << "process.loops must be a non-empty mapping"
      else
        loops.each do |name, row|
          unless row.is_a?(Hash)
            errors << "process.loops.#{name} must be a mapping"
            next
          end
          errors << "process.loops.#{name}.env must be an environment variable name" unless
            row["env"].is_a?(String) && row["env"].match?(/\A[A-Z][A-Z0-9_]*\z/)
          %w[max_run_seconds min_sleep_seconds].each do |field|
            number = row[field]
            errors << "process.loops.#{name}.#{field} must be non-negative numeric" unless
              number.is_a?(Numeric) && number >= 0
          end
        end
      end
      %w[load resources].each do |section|
        mapping = value[section]
        unless mapping.is_a?(Hash) && !mapping.empty?
          errors << "process.#{section} must be a non-empty mapping"
          next
        end
        mapping.each do |name, thresholds|
          label = "process.#{section}.#{name}"
          if section == "resources" && thresholds.is_a?(Hash) && thresholds.key?("darwin")
            baseline = thresholds.reject { |key, _entry| key == "darwin" }
            validate_threshold_row(baseline, label, errors)
            validate_threshold_row(thresholds["darwin"], "#{label}.darwin", errors)
          else
            validate_threshold_row(thresholds, label, errors)
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

      strict_keys(value, %w[tree tree_max_bytes read_in_full], "orientation", errors)
      errors << "orientation.tree must be non-empty text" unless value["tree"].is_a?(String) && !value["tree"].empty?
      errors << "orientation.tree_max_bytes must be a positive integer" unless
        value["tree_max_bytes"].is_a?(Integer) && value["tree_max_bytes"].positive?
      errors << "orientation.read_in_full must be non-empty text" unless
        value["read_in_full"].is_a?(String) && !value["read_in_full"].strip.empty?
    end

    def validate_governor(value, errors)
      return unless value.is_a?(Hash)

      strict_keys(value, %w[rate_limits auto_allowlist auto_dangerous_budget], "governor", errors)
      limits = value["rate_limits"]
      unless limits.is_a?(Hash) && !limits.empty? &&
             limits.all? { |tier, amount| tier.is_a?(String) && amount.is_a?(Numeric) && amount.positive? }
        errors << "governor.rate_limits must map tiers to positive numeric limits"
      end
      validate_auto_gates(value, errors)
    end

    # The unattended dangerous-tier gates Fix::Governor reads: exact tool names, and a budget of zero or more.
    def validate_auto_gates(value, errors)
      allowlist = value.fetch("auto_allowlist", [])
      errors << "governor.auto_allowlist must be a list of tool names" unless
        allowlist.is_a?(Array) && allowlist.all? { |name| name.is_a?(String) && !name.empty? }
      budget = value.fetch("auto_dangerous_budget", 0)
      errors << "governor.auto_dangerous_budget must be a non-negative integer" unless
        budget.is_a?(Integer) && budget >= 0
    end

    def strict_keys(value, allowed, label, errors)
      unknown = value.keys.map(&:to_s) - allowed
      errors << "#{label} has unknown field(s): #{unknown.sort.join(', ')}" unless unknown.empty?
    end
  end
end
