# frozen_string_literal: true

module MASTER
  # ConfirmationGate - Three-phase commit gate for destructive operations
  # Phases: propose → confirm → execute
  # Defaults to interactive TTY confirmation, can be automated for testing
  module ConfirmationGate
    extend self

    @auto_confirm = false

    class << self
      attr_accessor :auto_confirm
    end

    # Stage class for pipeline integration
    class Stage
      attr_reader :name, :status, :result

      def initialize(name, &block)
        @name = name
        @block = block
        @status = :pending
        @result = nil
      end

      def execute(context = {})
        @status = :running
        @result = @block.call(context)
        @status = @result.ok? ? :success : :failed
        @result
      rescue StandardError => e
        @status = :failed
        @result = Result.err("Stage #{@name} failed: #{e.message}")
        @result
      end

      def success?
        @status == :success
      end

      def failed?
        @status == :failed
      end
    end

    def gate(operation, details: nil, auto_confirm: nil, &block)
      # Phase 1: Propose
      proposal = propose(operation, details)
      return Result.err("Proposal rejected: #{proposal[:reason]}") unless proposal[:valid]

      # Phase 2: Confirm
      confirmed = confirm_operation(operation, details, auto_confirm)
      return Result.err("Operation cancelled by user") unless confirmed

      # Phase 3: Execute
      execute_operation(operation, details, &block)
    end

    def propose(operation, details)
      # Check if operation is destructive
      destructive = destructive_operation?(operation)

      # Check Constitution if available
      if defined?(MASTER::Constitution)
        check = Constitution.check_operation(operation, details || {})
        return { valid: false, reason: check.failure } if check.err?
      end

      {
        valid: true,
        operation: operation,
        details: details,
        destructive: destructive,
      }
    end

    def confirm_operation(operation, details, auto_confirm_override = nil)
      # Use override if provided, otherwise use module setting
      should_auto_confirm = auto_confirm_override.nil? ? @auto_confirm : auto_confirm_override

      return true if should_auto_confirm

      # Interactive confirmation
      if destructive_operation?(operation)
        confirm_destructive(operation, details)
      else
        true
      end
    end

    def execute_operation(operation, details)
      return Result.err("No block provided") unless block_given?

      result = yield(operation, details)

      if result.is_a?(Result)
        result
      elsif result
        Result.ok(value: result)
      else
        Result.err("Operation returned false or nil")
      end
    rescue StandardError => e
      Result.err("Execution failed: #{e.message}")
    end

    def destructive_operation?(operation)
      DESTRUCTIVE_OPS.include?(operation.to_sym)
    end

    DESTRUCTIVE_OPS = [
      :delete_file,
      :truncate_file,
      :overwrite_file,
      :drop_table,
      :reset_database,
      :modify_protected_file,
      :execute_shell_destructive,
      :self_modify,
    ].freeze

    private

    def confirm_destructive(operation, details)
      message = build_confirmation_message(operation, details)

      if tty_available?
        confirm_with_tty(message)
      else
        confirm_with_stdin(message)
      end
    end

    def build_confirmation_message(operation, details)
      msg = "⚠️  Destructive Operation: #{operation.to_s.tr('_', ' ')}"
      msg += "\n  #{details}" if details.is_a?(String)

      if details.is_a?(Hash)
        details.each do |key, value|
          msg += "\n  #{key}: #{value}"
        end
      end

      msg += "\n\nProceed?"
      msg
    end

    def tty_available?
      $stdin.tty? && defined?(TTY::Prompt)
    end

    def confirm_with_tty(message)
      if defined?(TTY::Prompt)
        prompt = TTY::Prompt.new
        prompt.yes?(message)
      else
        confirm_with_stdin(message)
      end
    rescue StandardError
      confirm_with_stdin(message)
    end

    def confirm_with_stdin(message)
      puts message
      print "Type 'yes' to confirm: "
      response = $stdin.gets&.strip&.downcase
      response == "yes"
    end
  end
end
