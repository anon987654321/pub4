# frozen_string_literal: true

module MASTER
  # ConfirmationGate - User approval workflow for sensitive operations
  module ConfirmationGate
    extend self

    @auto_confirm = false

    class << self
      attr_accessor :auto_confirm
    end

    # Gate operation with three phases: propose → confirm → execute
    def gate(operation_name, description: nil, &block)
      return Result.err("No block provided") unless block

      # Phase 1: Propose
      if description
        puts "\n"
        puts "  ⚠️  Operation: #{operation_name}"
        puts "  📋 Description: #{description}"
        puts "\n"
      else
        puts "\n  ⚠️  Operation: #{operation_name}\n\n"
      end

      # Phase 2: Confirm
      unless @auto_confirm
        # Delegate to Confirmations module for actual confirmation
        confirmed = Confirmations.confirm("Proceed with this operation?")

        unless confirmed
          return Result.err("Cancelled by user")
        end
      end

      # Phase 3: Execute
      begin
        result = block.call
        Result.ok(result: result)
      rescue StandardError => e
        Result.err("Execution failed: #{e.message}")
      end
    end

    # Stage class for pipeline integration
    class Stage
      def initialize(operation_name, description: nil)
        @operation_name = operation_name
        @description = description
      end

      def call(context)
        ConfirmationGate.gate(@operation_name, description: @description) do
          context
        end
      end
    end
  end
end
