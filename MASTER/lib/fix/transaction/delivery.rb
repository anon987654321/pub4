# frozen_string_literal: true

module Master
  module Fix
    class Transaction
      # The five delivery-state methods, unchanged, reached through
      # Transaction#delivery. Every method here reads/writes the owning
      # Transaction's own ivars and calls its own persist!/emit via send, so
      # the manifest this writes and the events it publishes are byte- and
      # name-identical to before the split -- this class adds no state of its
      # own beyond the reference back to tx.
      class Delivery
        def initialize(tx)
          @tx = tx
        end

        def begin!(head_before:)
          raise "transaction not active" unless @tx.send(:active?)
          raise "transaction is not open: #{@tx.state}" unless @tx.state == "open"

          @tx.instance_variable_set(:@state, "delivering")
          @tx.instance_variable_set(:@delivery_head_before, head_before.to_s)
          @tx.instance_variable_set(:@delivery_head_after, nil)
          @tx.send(:persist!)
          @tx.send(:emit, "fix:transaction_delivery_start", id: @tx.id, paths: @tx.instance_variable_get(:@paths),
                                                             head_before: head_before.to_s)
          true
        end

        def record_commit!(head_after:)
          raise "transaction not active" unless @tx.send(:active?)
          raise "transaction is not delivering" unless @tx.state == "delivering"

          @tx.instance_variable_set(:@delivery_head_after, head_after.to_s)
          @tx.send(:persist!)
          true
        end

        def pending?
          @tx.state == "delivering" && !@tx.instance_variable_get(:@delivery_head_after).to_s.empty?
        end

        def head_after = @tx.instance_variable_get(:@delivery_head_after)

        def finalize!(head:)
          raise "transaction is not pending delivery" unless pending?
          raise "delivery HEAD mismatch" unless head.to_s == head_after

          @tx.instance_variable_set(:@state, "committed")
          @tx.instance_variable_set(:@active, false)
          @tx.send(:persist!)
          @tx.send(:cleanup!)
          @tx.send(:release_lock)
          @tx.send(:emit, "fix:transaction_delivery_recovered", id: @tx.id, commit: head.to_s)
          Result.ok(:committed)
        rescue StandardError => e
          @tx.send(:emit, "fix:transaction_delivery_finalize_failed", id: @tx.id, error: e.message)
          Result.err("transaction delivery finalize: #{e.message}", category: :infrastructure)
        end

        # Public: committer.rb's crash handler calls this on a transaction
        # that was still active when an unexpected error hit, regardless of
        # state -- unlike recover! below, this is not delivery-specific, so
        # it stays reachable from outside Transaction/Delivery.
        def preserve!
          @tx.instance_variable_set(:@active, false)
          @tx.send(:release_lock)
          Result.ok(:preserved_delivery)
        end

        private

        # Called only from Transaction#recover! while @state == "delivering".
        def recover!
          @tx.instance_variable_set(:@active, false)
          @tx.send(:release_lock)
          if pending?
            @tx.send(:emit, "fix:transaction_delivery_pending", id: @tx.id, commit: head_after)
            Result.ok({ state: :delivery_pending, commit: head_after, transaction_id: @tx.id })
          else
            @tx.send(:emit, "fix:transaction_delivery_unknown", id: @tx.id,
                                                                 reason: "delivery started before commit identity was recorded")
            Result.err("transaction delivery state is ambiguous; manual review required", category: :policy)
          end
        end
      end
    end
  end
end
