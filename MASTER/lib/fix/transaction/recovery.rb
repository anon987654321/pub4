# frozen_string_literal: true

module Master
  module Fix
    class Transaction
      # The four callers who need to find or rebuild a Transaction from its
      # persisted id (rather than build a fresh one) -- moved out because
      # Transaction's own instance API alone already fills its budget.
      # Recovery holds no state of its own; every method here constructs or
      # loads a real Transaction and hands back what that instance already
      # does.
      class Recovery
        class << self
          def persisted?(root:, id:)
            safe = Transaction.send(:normalize_id, id)
            File.file?(File.join(File.expand_path(root), ROOT_DIR, safe, MANIFEST))
          rescue ArgumentError
            false
          end

          def load_persisted(root:, id:, bus: nil)
            transaction = Transaction.new(root:, paths: [], id:, bus:)
            unless transaction.send(:acquire_lock, nonblock: true)
              raise "transaction load refused: an active transaction holds the root lock"
            end

            transaction.send(:load_manifest!)
            transaction
          rescue StandardError
            transaction&.send(:release_lock)
            raise
          end

          # release_conflicts: true is the next run's sweep of a dead process's pass: files another
          # writer changed since leave the transaction and the pass's own writes roll back. Without
          # it one such file refused the whole rollback, and the dead pass's edits stayed everywhere.

          def recover!(root:, id:, bus: nil, release_conflicts: false)
            # Construct without loading the manifest: Transaction#recover! must
            # acquire the root lock before it reads recovery state.
            Transaction.new(root:, paths: [], id:, bus:).send(:recover!, release_conflicts:)
          end
        end
      end
    end
  end
end
