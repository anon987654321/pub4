# frozen_string_literal: true

module Master
  module Fix
    class Transaction
      # The delivering state machine, reached through Transaction#delivery. It
      # keeps no state: it changes the Transaction only through that class's
      # delivery door, so the manifest and events stay the Transaction's own.
      class Delivery
        def initialize(transaction) = (@tx = transaction)

        # The line the Committer writes into each delivery commit's body, so a
        # recovery can find the commit a crash kept the manifest from naming.
        def self.marker(id) = "fix transaction #{id}"

        # paths are the ones this delivery will commit. A sacred one ends it before
        # anything is marked: no automated writer may change one.
        def begin!(head_before:, paths: [])
          raise "transaction not active" unless @tx.active?
          raise "transaction is not open: #{@tx.state}" unless @tx.state == "open"

          refuse_sacred!(paths)

          @tx.update_delivery!(:delivery_begin, state: "delivering", head_before: head_before.to_s,
                                                head_after: nil, marked: true)
          @tx.delivery_event("fix:transaction_delivery_start", id: @tx.id, paths: @tx.enlisted_paths,
                                                                head_before: head_before.to_s)
        end

        def record_commit!(head_after:)
          raise "transaction not active" unless @tx.active?
          raise "transaction is not delivering" unless @tx.state == "delivering"

          @tx.update_delivery!(:record_commit, head_after: head_after.to_s)
        end

        def pending?
          @tx.state == "delivering" && !head_after.to_s.empty?
        end

        def head_after = @tx.delivery_head_after

        def finalize!(head:)
          raise "transaction is not pending delivery" unless pending?
          raise "delivery HEAD mismatch" unless head.to_s == head_after

          @tx.update_delivery!(:delivery_finalize, state: "committed", active: false)
          @tx.close!(cleanup: true)
          @tx.delivery_event("fix:transaction_delivery_recovered", id: @tx.id, commit: head.to_s)
          Result.ok(:committed)

        rescue StandardError => e
          @tx.delivery_event("fix:transaction_delivery_finalize_failed", id: @tx.id, error: e.message)
          # The Result is the operator's answer, not the durable manifest: it names the reason.
          Result.err("transaction delivery finalize: #{e.class}: #{e.message}", category: :infrastructure)
        ensure
          # A loaded recovery transaction owns the root lock; a rejected finalization
          # must not strand the repository behind a lock only this object holds.
          @tx.close!
        end

        # committer.rb's crash handler calls this on a transaction that was
        # still active when an unexpected error hit, whatever its state; the
        # manifest is left as it stands for recovery to read.
        def preserve!
          @tx.update_delivery!(persist: false, active: false)
          @tx.close!
          Result.ok(:preserved_delivery)
        end

        # Called by Transaction's recovery while the manifest says "delivering".
        # :not_committed tells the Transaction to roll the pass back like an open one.
        def recover!
          return :not_committed if settle_from_git == :not_committed

          @tx.update_delivery!(persist: false, active: false)
          @tx.close!
          return pending_result if pending?

          @tx.delivery_event("fix:transaction_delivery_unknown",
                             id: @tx.id, reason: "delivery started before commit identity was recorded")
          Result.err("transaction delivery state is ambiguous; manual review required", category: :policy)
        end

        private

        # A process that died between its commit and record_commit! left no
        # head_after. A marked delivery is settled from git: the commit carrying its
        # marker is the head to finalise, and no such commit means it never landed.
        def settle_from_git
          return if pending? || !@tx.delivery_marked?

          case (landed = landed_commit)
          when String
            @tx.update_delivery!(head_after: landed)
          when false
            @tx.update_delivery!(state: "open")
            @tx.delivery_event("fix:transaction_delivery_not_committed", id: @tx.id)
            :not_committed
          end
        end

        def pending_result
          @tx.delivery_event("fix:transaction_delivery_pending", id: @tx.id, commit: head_after)
          Result.ok({ state: :delivery_pending, commit: head_after, transaction_id: @tx.id })
        end

        def refuse_sacred!(paths)
          root = @tx.root
          Array(paths).each do |path|
            reason = Master::Core::Constitution::Paths.write_refusal(path, root:)
            next unless reason

            Master::Fix::Refusals.record(gate: :commit, file: File.expand_path(path, root),
                                         reason: "sacred_path: #{reason}", root:)
            raise "transaction delivery refused: #{reason}"
          end
        end

        # The newest commit since head_before whose body carries the marker;
        # false when git answered and none does; nil when git could not say.
        def landed_commit
          before = @tx.delivery_head_before.to_s
          return nil if before.empty?

          out, status = Master::Io::Exec.capture2e(
            "git", "-C", @tx.root, "log", "--format=%H", "--fixed-strings",
            "--grep=#{self.class.marker(@tx.id)}", "#{before}..HEAD"
          )
          return nil unless status.success?

          out.lines.first&.strip || false
        end
      end
    end
  end
end
