# frozen_string_literal: true

module Master
  module Fix
    # Syspatch-shaped unit of self-change. Transaction owns the durable
    # checkpoint; Patch owns the apply -> verify -> rollback decision.
    class Patch
      Result = Data.define(:state, :value, :proof)

      def initialize(transaction:, apply:, verify:)
        @transaction = transaction
        @apply = apply
        @verify = verify
      end

      def run
        value = @apply.call
        proof = @verify.call(value)

        return Result.new(:installed, value, proof) if proof

        rollback = @transaction.rollback!
        Result.new(:reverted, value, rollback)
      rescue StandardError
        @transaction.rollback! if @transaction.respond_to?(:active?) && @transaction.active?
        raise
      end
    end
  end
end
