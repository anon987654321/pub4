# frozen_string_literal: true

require 'yaml'
require 'time'
require 'fileutils'

module MASTER
  # Event system for lifecycle hooks
  # Manages events: before_edit, after_fix, before_commit, on_stuck, on_oscillation
  module HooksManager
    extend self

    EVENTS = %i[
      before_edit after_edit
      before_fix after_fix
      before_commit after_commit
      before_phase after_phase
      on_stuck on_oscillation on_error
      on_budget_low
    ].freeze

    def hooks
      @hooks ||= begin
        config = load_config
        config
      end
    end

    def register(event, handler)
      Result.try do
        raise "Unknown event: #{event}" unless EVENTS.include?(event.to_sym)
        raise "Handler must respond to :call" unless handler.respond_to?(:call)

        @handlers ||= {}
        @handlers[event.to_sym] ||= []
        @handlers[event.to_sym] << handler
        
        { event: event, handlers: @handlers[event.to_sym].size }
      end
    end

    def unregister(event, handler = nil)
      Result.try do
        @handlers ||= {}
        if handler
          @handlers[event.to_sym]&.delete(handler)
        else
          @handlers[event.to_sym] = []
        end
        
        { event: event, cleared: handler.nil? }
      end
    end

    def dispatch(event, data = {})
      Result.try do
        raise "Unknown event: #{event}" unless EVENTS.include?(event.to_sym)

        results = []
        hook_names = hooks[event.to_s] || hooks[event] || []
        
        hook_names.each do |hook_name|
          result = execute_hook(hook_name, data)
          results << { hook: hook_name, result: result }
        end

        # Also call registered runtime handlers
        @handlers ||= {}
        @handlers[event.to_sym]&.each do |handler|
          result = execute_handler(handler, data)
          results << { handler: handler.class.name, result: result }
        end

        {
          event: event,
          executed: results.size,
          results: results,
          success: results.all? { |r| r[:result].is_a?(Result) ? r[:result].ok? : true }
        }
      end
    end

    def dispatch_with_rollback(event, data = {}, &rollback_block)
      result = dispatch(event, data)
      
      if result.ok? && result.value[:success]
        result
      else
        rollback_block&.call(result)
        Result.err("Hook execution failed: #{result.error || 'partial failure'}")
      end
    end

    def clear_handlers
      @handlers = {}
      Result.ok({ cleared: true })
    end

    private

    def load_config
      path = File.join(MASTER.root, 'data', 'hooks.yml')
      YAML.load_file(path)
    rescue Errno::ENOENT
      default_hooks
    end

    def default_hooks
      {
        'before_edit' => ['backup_original', 'validate_syntax', 'check_tests_pass'],
        'after_fix' => ['validate_syntax', 'run_affected_tests', 'check_principles'],
        'before_commit' => ['full_test_suite', 'security_scan', 'lint_check'],
        'on_stuck' => ['broaden_search', 'change_perspective', 'escalate_to_user'],
        'on_oscillation' => ['freeze_state', 'analyze_cycle', 'break_deadlock'],
        'on_error' => ['log_context', 'suggest_fix', 'offer_rollback'],
        'on_budget_low' => ['warn_user', 'switch_to_cheap_tier', 'summarize_session']
      }
    end

    def execute_hook(hook_name, data)
      # Hook execution is a placeholder for now
      # In a full implementation, these would map to actual methods
      case hook_name.to_s
      when 'backup_original'
        backup_file(data[:file_path]) if data[:file_path]
      when 'validate_syntax'
        validate_syntax(data[:code] || data[:content]) if data[:code] || data[:content]
      when 'log_context'
        log_event(hook_name, data)
      else
        # Default: log that hook was called
        Result.ok({ hook: hook_name, executed: true })
      end
    rescue StandardError => e
      Result.err("Hook #{hook_name} failed: #{e.message}")
    end

    def execute_handler(handler, data)
      handler.call(data)
      Result.ok({ executed: true })
    rescue StandardError => e
      Result.err("Handler failed: #{e.message}")
    end

    def backup_file(file_path)
      return Result.err("No file path") unless file_path
      return Result.ok({ skipped: true }) unless File.exist?(file_path)

      backup_path = "#{file_path}.bak"
      FileUtils.cp(file_path, backup_path)
      Result.ok({ backed_up: backup_path })
    rescue StandardError => e
      Result.err("Backup failed: #{e.message}")
    end

    def validate_syntax(code)
      return Result.err("No code provided") unless code
      
      # Simple Ruby syntax check
      if code.is_a?(String) && code.include?('def ')
        RubyVM::InstructionSequence.compile(code)
        Result.ok({ valid: true })
      else
        Result.ok({ skipped: true, reason: 'not Ruby code' })
      end
    rescue SyntaxError => e
      Result.err("Syntax error: #{e.message}")
    rescue StandardError => e
      Result.ok({ skipped: true, reason: e.message })
    end

    def log_event(hook_name, data)
      # Simple logging - in production would use proper logger
      Result.ok({ logged: true, hook: hook_name, timestamp: Time.now.iso8601 })
    end
  end
end
