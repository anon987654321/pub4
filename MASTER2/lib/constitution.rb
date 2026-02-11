# frozen_string_literal: true

require "yaml"

module MASTER
  module Constitution
    extend self

    @rules_cache = nil
    @axioms_cache = nil
    @council_cache = nil
    @principles_cache = nil
    @workflows_cache = nil

    def rules
      return @rules_cache if @rules_cache

      constitution_path = File.join(MASTER.root, "data", "constitution.yml")
      
      @rules_cache = if File.exist?(constitution_path)
        YAML.load_file(constitution_path)
      else
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

    def axioms
      return @axioms_cache if @axioms_cache
      
      if rules["axioms"]
        @axioms_cache = rules["axioms"]
      else
        axioms_path = File.join(MASTER.root, "data", "axioms.yml")
        @axioms_cache = File.exist?(axioms_path) ? YAML.load_file(axioms_path) : []
      end
      
      @axioms_cache
    end

    def council
      return @council_cache if @council_cache
      
      if rules["council"]
        @council_cache = rules["council"]
      else
        council_path = File.join(MASTER.root, "data", "council.yml")
        @council_cache = File.exist?(council_path) ? YAML.load_file(council_path) : []
      end
      
      @council_cache
    end

    def principles
      return @principles_cache if @principles_cache
      
      @principles_cache = rules["principles"] || {}
      @principles_cache
    end

    def workflows
      return @workflows_cache if @workflows_cache
      
      @workflows_cache = rules["workflows"] || {}
      @workflows_cache
    end

    def reload!
      @rules_cache = nil
      @axioms_cache = nil
      @council_cache = nil
      @principles_cache = nil
      @workflows_cache = nil
      rules
    end

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

    def permission?(tool)
      granted = rules.dig("tool_permissions", "granted") || []
      granted.include?(tool.to_s)
    end

    def protected_file?(path)
      protected = rules["protected_paths"] || []
      expanded = File.expand_path(path)
      
      protected.any? do |protected_path|
        expanded_protected = if protected_path.start_with?("/")
          protected_path
        else
          File.expand_path(protected_path, MASTER.root)
        end
        
        expanded.start_with?(expanded_protected) || expanded == expanded_protected
      end
    end

    def limit(key)
      rules.dig("resource_limits", key.to_s)
    end

    private

    def check_shell_command(cmd)
      blocked = rules.dig("shell_patterns", "blocked") || []
      allowed = rules.dig("shell_patterns", "allowed") || []
      
      blocked.each do |pattern|
        if cmd.include?(pattern) || cmd.match?(Regexp.new(pattern))
          return Result.err("Shell command blocked by constitution: #{pattern}")
        end
      end
      
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
