# frozen_string_literal: true

require "yaml"
require "time"
require "fileutils"
require "shellwords"

module MASTER
  # Hooks - Lifecycle event handlers
  # Executes registered actions at key pipeline moments
  module Hooks
    HOOKS_FILE = File.join(__dir__, "..", "data", "hooks.yml")

    # Events supported by the hook system
    EVENTS = %i[
      before_edit after_edit
      before_fix after_fix
      before_commit after_commit
      before_phase after_phase
      on_stuck on_oscillation on_error
      on_budget_low
    ].freeze

    class << self
      def config
        @config ||= load_config
      end

      def load_config
        return {} unless File.exist?(HOOKS_FILE)
        YAML.safe_load_file(HOOKS_FILE) || {}
      end

      def run(event, context = {})
        Logging.dmesg_log('hooks', message: 'ENTER hooks.run')
        actions = config[event.to_s] || []
        results = []

        actions.each do |action|
          result = execute_action(action, context)
          results << { action: action, result: result }
          log("hooks0: #{event}.#{action} #{result ? '✓' : '✗'}")
        end

        results
      end

      def before_edit(context = {})
        run(:before_edit, context)
      end

      def after_fix(context = {})
        run(:after_fix, context)
      end

      def on_stuck(context = {})
        run(:on_stuck, context)
      end

      def on_oscillation(context = {})
        run(:on_oscillation, context)
      end

      def on_error(context = {})
        run(:on_error, context)
      end

      def on_budget_low(context = {})
        run(:on_budget_low, context)
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
          hook_names = config[event.to_s] || []

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

      def execute_action(action, context)
        case action.to_s
        when "backup_original"
          backup_file(context[:file]) if context[:file]
        when "validate_syntax"
          validate_ruby_syntax(context[:file] || context[:code])
        when "check_tests_pass"
          run_tests
        when "broaden_search"
          context[:broadened] = true
        when "change_perspective"
          context[:perspective_changed] = true
        when "escalate_to_user"
          UI.warn("Escalating to user - stuck on: #{context[:issue]}")
          false
        when "freeze_state"
          context[:frozen] = true
        when "analyze_cycle"
          if defined?(Convergence)
            Convergence.analyze_oscillation(context[:history] || [])
          else
            false
          end
        when "warn_user"
          UI.warn("Budget low: #{UI.currency(LLM.budget_remaining)} remaining")
        when "switch_to_cheap_tier"
          true # LLM auto-switches based on budget
        else
          true # Unknown action, assume success
        end
      rescue StandardError => e
        log("hooks0: #{action} error: #{e.message}")
        false
      end

      def backup_file(file)
        return false unless file && File.exist?(file)
        backup = "#{file}.bak"
        FileUtils.cp(file, backup)
        true
      end

      def validate_ruby_syntax(target)
        return true unless target
        if File.exist?(target.to_s)
          # Use array form to avoid shell interpretation - prevents injection attacks
          system("ruby", "-c", target.to_s, out: File::NULL, err: File::NULL)
        else
          MASTER::Utils.valid_ruby?(target.to_s)
        end
      end

      def run_tests
        test_dir = File.join(MASTER::Paths.root, "test")
        return Result.err("No test directory") unless Dir.exist?(test_dir)

        test_files = Dir[File.join(test_dir, "**", "*_test.rb")] +
                     Dir[File.join(test_dir, "**", "test_*.rb")]
        return Result.err("No test files found") if test_files.empty?

        output = `ruby -e "ARGV.each { |f| load f }" #{test_files.map { |f| Shellwords.escape(f) }.join(" ")} 2>&1`
        $?.success? ? Result.ok("Tests passed") : Result.err("Tests failed: #{output.lines.last(5).join}")
      end

      def log(msg)
        puts UI.dim(msg)
      end

      def execute_hook(hook_name, data)
        execute_action(hook_name, data)
      end

      def execute_handler(handler, data)
        handler.call(data)
        Result.ok({ executed: true })
      rescue StandardError => e
        Result.err("Handler failed: #{e.message}")
      end
    end
  end

  HooksManager = Hooks
end
