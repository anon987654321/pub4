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

          @tx.send(:lifecycle_mutation, :delivery_begin, item_count: @tx.instance_variable_get(:@paths).size) do
            @tx.instance_variable_set(:@state, "delivering")
            @tx.instance_variable_set(:@delivery_head_before, head_before.to_s)
            @tx.instance_variable_set(:@delivery_head_after, nil)
            @tx.instance_variable_set(:@delivery_marked, true)
            @tx.send(:persist!)
            true
          end
          @tx.send(:emit, "fix:transaction_delivery_start", id: @tx.id,
                                                            paths: @tx.instance_variable_get(:@paths),
                                                            head_before: head_before.to_s)
        end

        def record_commit!(head_after:)
          raise "transaction not active" unless @tx.send(:active?)
          raise "transaction is not delivering" unless @tx.state == "delivering"

          @tx.send(:lifecycle_mutation, :record_commit, item_count: @tx.instance_variable_get(:@paths).size) do
            @tx.instance_variable_set(:@delivery_head_after, head_after.to_s)
            @tx.send(:persist!)
            true
          end
        end

        def pending?
          @tx.state == "delivering" && !@tx.instance_variable_get(:@delivery_head_after).to_s.empty?
        end

        def head_after = @tx.instance_variable_get(:@delivery_head_after)

        def finalize!(head:)
          raise "transaction is not pending delivery" unless pending?
          raise "delivery HEAD mismatch" unless head.to_s == head_after

          @tx.send(:lifecycle_mutation, :delivery_finalize, item_count: @tx.instance_variable_get(:@paths).size) do
            @tx.instance_variable_set(:@state, "committed")
            @tx.instance_variable_set(:@active, false)
            @tx.send(:persist!)
            Result.ok(:committed)
          end
          @tx.send(:cleanup!)
          @tx.send(:release_lock)
          @tx.send(:emit, "fix:transaction_delivery_recovered", id: @tx.id, commit: head.to_s)
          Result.ok(:committed)
        rescue StandardError => e
          @tx.send(:emit, "fix:transaction_delivery_finalize_failed", id: @tx.id, error: e.message)
          # The Result is the operator's answer, not the durable manifest: it names the reason.
          Result.err("transaction delivery finalize: #{e.class}: #{e.message}", category: :infrastructure)
        ensure
          # A loaded recovery transaction owns the root lock. Release it on both
          # success and failure so a rejected/mismatched finalization cannot
          # strand the repository behind a lock held only by this Ruby object.
          @tx.send(:release_lock)
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

        # The line the Committer writes into each delivery commit's body, so a
        # recovery can find the commit a crash kept the manifest from naming.
        def self.marker(id) = "fix transaction #{id}"

        # Called only from Transaction#recover! while @state == "delivering".
        # A process that died between its commit and record_commit! left no
        # head_after. A marked delivery is settled from git: the commit that
        # carries its marker is the head to finalise, and no such commit means
        # it never landed, so the pass rolls back like an open one.
        def recover!
          if !pending? && @tx.instance_variable_get(:@delivery_marked)
            case (landed = landed_commit)
            when String
              @tx.instance_variable_set(:@delivery_head_after, landed)
              @tx.send(:persist!)
            when false
              @tx.instance_variable_set(:@state, "open")
              @tx.send(:persist!)
              @tx.send(:emit, "fix:transaction_delivery_not_committed", id: @tx.id)
              return @tx.send(:recover_open_state)
            end
          end
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

        # The newest commit since head_before whose body carries the marker;
        # false when git answered and none does; nil when git could not say.
        def landed_commit
          before = @tx.instance_variable_get(:@delivery_head_before).to_s
          return nil if before.empty?

          out, status = Master::Io::Exec.capture2e(
            "git", "-C", @tx.instance_variable_get(:@root), "log", "--format=%H", "--fixed-strings",
            "--grep=#{self.class.marker(@tx.id)}", "#{before}..HEAD"
          )
          return nil unless status.success?

          out.lines.first&.strip || false
        end
      end
    end
  end
end
