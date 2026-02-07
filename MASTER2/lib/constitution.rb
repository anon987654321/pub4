# frozen_string_literal: true

require "yaml"

module MASTER
  # Constitution - Enforcement of governance policies for safe autonomous operation
  module Constitution
    extend self

    @rules_cache = nil

    # Load and cache constitution rules, with sensible defaults if file is missing
    def rules
      return @rules_cache if @rules_cache

      constitution_path = File.join(MASTER.root, "data", "constitution.yml")
      
      @rules_cache = if File.exist?(constitution_path)
        YAML.load_file(constitution_path)
      else
        # Sensible defaults when constitution.yml is missing
        {
          "safety_policies" => {
            "self_modification" => { "require_staging" => true },
            "environment_control" => { "direct_control" => false }
          },
          "tool_permissions" => {
            "granted" => ["shell_command", "code_execution", "file_write"]
          },
          "shell_patterns" => {
            "allowed" => ["^(ls|pwd|echo|git|cat|head|tail|wc|find|grep)", "^ruby", "^bundle"],
            "blocked" => ["rm -rf /", "DROP TABLE", "mkfs", "dd if=", ":(){ :|:& };:"]
          },
          "protected_paths" => ["data/constitution.yml", "/etc/", "/usr/", "/sys/"],
          "resource_limits" => {
            "max_file_size" => 1048576,
            "max_concurrent_tools" => 5,
            "max_staging_files" => 10,
            "max_shell_output" => 10000
          },
          "staging" => {
            "validation" => {
              "default_command" => "ruby -c",
              "require_tests" => true
            }
          }
        }
      end
      
      @rules_cache
    end

    # Validate operation against constitution rules
    def check_operation(op, context = {})
      case op
      when :self_modification
        if rules.dig("safety_policies", "self_modification", "require_staging")
          unless context[:staged]
            return Result.err("Self-modification requires staging")
          end
        end
        Result.ok
      
      when :environment_control
        if rules.dig("safety_policies", "environment_control", "direct_control") == false
          return Result.err("Direct environment control not permitted")
        end
        Result.ok
      
      when :shell_command
        cmd = context[:command] || ""
        check_shell_command(cmd)
      
      when :file_write
        path = context[:path] || ""
        check_file_write(path)
      
      else
        Result.ok
      end
    end

    # Check if a tool is permitted
    def permission?(tool)
      granted = rules.dig("tool_permissions", "granted") || []
      granted.include?(tool.to_s)
    end

    # Check if a path is protected
    def protected_file?(path)
      protected = rules["protected_paths"] || []
      expanded = File.expand_path(path)
      
      protected.any? do |protected_path|
        # For absolute paths, compare directly; for relative, expand from root
        expanded_protected = if protected_path.start_with?("/")
          protected_path
        else
          File.expand_path(protected_path, MASTER.root)
        end
        
        expanded.start_with?(expanded_protected) || expanded == expanded_protected
      end
    end

    # Get a resource limit value
    def limit(key)
      rules.dig("resource_limits", key.to_s)
    end

    private

    def check_shell_command(cmd)
      blocked = rules.dig("shell_patterns", "blocked") || []
      allowed = rules.dig("shell_patterns", "allowed") || []
      
      # Check blocked patterns first
      blocked.each do |pattern|
        if cmd.include?(pattern) || cmd.match?(Regexp.new(pattern))
          return Result.err("Shell command blocked by constitution: #{pattern}")
        end
      end
      
      # Check allowed patterns
      if allowed.any?
        unless allowed.any? { |pattern| cmd.match?(Regexp.new(pattern)) }
          return Result.err("Shell command not in allowed list")
        end
      end
      
      Result.ok
    end

    def check_file_write(path)
      if protected_file?(path)
        Result.err("File write to protected path: #{path}")
      else
        Result.ok
      end
    end
  end
end
