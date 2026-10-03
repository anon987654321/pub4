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
            transaction.send(:load_manifest!)
            transaction
          end

          def recover!(root:, id:, bus: nil)
            load_persisted(root:, id:, bus:).send(:recover!)
          end
        end
      end
    end
  end
end
