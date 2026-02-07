# frozen_string_literal: true

module MASTER
  # Constitution - Enforcement layer for constitution.yml
  # Immutable governance rules that MASTER2 cannot modify about itself
  module Constitution
    extend self

    DEFAULT_LIMITS = {
      max_file_size: 100_000,
      max_method_length: 50,
      max_class_length: 300,
      max_nesting_depth: 5,
      max_parameters: 5,
      max_concurrent_operations: 3,
      budget_threshold: 50.0,
    }.freeze

    DEFAULT_PERMISSIONS = {
      can_modify_config: true,
      can_modify_data: true,
      can_modify_lib: true,
      can_modify_bin: false,
      can_delete_files: false,
      can_execute_shell: true,
      can_use_llm: true,
      can_self_modify: true,
    }.freeze

    DEFAULT_PROTECTED = [
      "data/constitution.yml",
      "lib/constitution.rb",
      "lib/master.rb",
      "lib/result.rb",
      "lib/logging.rb",
    ].freeze

    def constitution_file
      File.join(MASTER.root, "data", "constitution.yml")
    end

    def rules
      @rules ||= load_rules
    end

    def load_rules
      if File.exist?(constitution_file)
        YAML.load_file(constitution_file, symbolize_names: true)
      else
        default_rules
      end
    rescue StandardError => e
      Logging.warn("Constitution: Failed to load #{constitution_file}: #{e.message}")
      default_rules
    end

    def default_rules
      {
        limits: DEFAULT_LIMITS,
        permissions: DEFAULT_PERMISSIONS,
        protected_files: DEFAULT_PROTECTED,
        protected_directories: [".git", ".github/agents"],
        principles: [],
        violation_actions: {
          protected_file_modification: "block",
          over_budget: "warn",
          over_complexity: "warn",
          missing_confirmation: "block",
        },
      }
    end

    def reload!
      @rules = nil
      load_rules
    end

    def check_operation(operation, context = {})
      case operation
      when :modify_file
        check_file_modification(context[:file])
      when :delete_file
        check_file_deletion(context[:file])
      when :execute_shell
        check_shell_execution(context[:command])
      when :use_llm
        check_llm_usage(context)
      when :self_modify
        check_self_modification(context[:file])
      else
        Result.ok(allowed: true)
      end
    end

    def permission?(key)
      rules.dig(:permissions, key.to_sym) || false
    end

    def protected_file?(file)
      return false unless file

      normalized = normalize_path(file)
      protected = rules[:protected_files] || DEFAULT_PROTECTED

      protected.any? do |pattern|
        if pattern.include?("*")
          File.fnmatch?(pattern, normalized, File::FNM_PATHNAME)
        else
          normalized.end_with?(pattern) || normalized.include?(pattern)
        end
      end
    end

    def protected_directory?(dir)
      return false unless dir

      normalized = normalize_path(dir)
      protected = rules[:protected_directories] || []

      protected.any? { |pd| normalized.start_with?(pd) || normalized.include?(pd) }
    end

    def limit(key)
      rules.dig(:limits, key.to_sym) || DEFAULT_LIMITS[key.to_sym]
    end

    def principles
      rules[:principles] || []
    end

    def violation_action(type)
      rules.dig(:violation_actions, type.to_sym) || "warn"
    end

    private

    def check_file_modification(file)
      return Result.err("No file specified") unless file

      if protected_file?(file)
        action = violation_action(:protected_file_modification)
        msg = "Cannot modify protected file: #{file}"
        return action == "block" ? Result.err(msg) : Result.ok(allowed: true, warning: msg)
      end

      Result.ok(allowed: true)
    end

    def check_file_deletion(file)
      return Result.err("File deletion not permitted") unless permission?(:can_delete_files)
      return Result.err("Cannot delete protected file: #{file}") if protected_file?(file)

      Result.ok(allowed: true)
    end

    def check_shell_execution(command)
      return Result.err("Shell execution not permitted") unless permission?(:can_execute_shell)

      Result.ok(allowed: true)
    end

    def check_llm_usage(context)
      return Result.err("LLM usage not permitted") unless permission?(:can_use_llm)

      budget = context[:cost] || 0
      threshold = limit(:budget_threshold)

      if budget > threshold
        action = violation_action(:over_budget)
        msg = "Budget $#{budget} exceeds threshold $#{threshold}"
        return action == "block" ? Result.err(msg) : Result.ok(allowed: true, warning: msg)
      end

      Result.ok(allowed: true)
    end

    def check_self_modification(file)
      return Result.err("Self-modification not permitted") unless permission?(:can_self_modify)

      if protected_file?(file)
        msg = "Cannot self-modify protected file: #{file}"
        action = violation_action(:protected_file_modification)
        return action == "block" ? Result.err(msg) : Result.ok(allowed: true, warning: msg)
      end

      Result.ok(allowed: true)
    end

    def normalize_path(path)
      path.to_s.sub(%r{^#{Regexp.escape(MASTER.root)}/?}, "")
    end
  end
end
