# frozen_string_literal: true

require "yaml"

module MASTER
  # Hooks - Lifecycle event handlers
  # Executes registered actions at key pipeline moments
  module Hooks
    HOOKS_FILE = File.join(__dir__, "..", "data", "hooks.yml")

    class << self
      def config
        @config ||= load_config
      end

      def load_config
        return {} unless File.exist?(HOOKS_FILE)
        YAML.safe_load_file(HOOKS_FILE) || {}
      end

      def run(event, context = {})
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
          Convergence.analyze_oscillation(context[:history] || [])
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
          # For code strings, use RubyVM::InstructionSequence for parse-only validation
          begin
            RubyVM::InstructionSequence.compile(target.to_s)
            true
          rescue SyntaxError
            false
          end
        end
      end

      def run_tests
        # Placeholder - not yet implemented
        Result.err("run_tests not yet implemented")
      end

      def log(msg)
        puts UI.dim(msg)
      end
    end
  end
end
