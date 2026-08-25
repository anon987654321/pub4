# frozen_string_literal: true

module Master
  module Trace
    module Ledger
      # Tallies swallow:error events per context — a spike in one context is a defect, not noise.
      class Swallow
        LEDGER_PATH = "runtime/swallow_ledger.jsonl"
        SNAPSHOT_EVERY = 50

        def initialize(event_bus:, root: Master::ROOT)
          @bus = event_bus
          @root = root
          @counts = Hash.new(0)
          @total = 0
          @mutex = Mutex.new
        end

        # Subscribe to the swallow stream. Call once at boot.
        def attach
          @bus&.subscribe("swallow:error") { |payload| record(payload) }
          self
        end

        # context => count. Used by /axioms and tests.
        def snapshot = @mutex.synchronize { @counts.dup }

        def total = @mutex.synchronize { @total }

        private

        def record(payload)
          context = payload[:context] || payload["context"] || "unknown"
          flush if tally(context)
        end

        # Increment under lock; true when a snapshot flush is due.
        def tally(context)
          @mutex.synchronize do
            @counts[context] += 1
            @total += 1
            (@total % SNAPSHOT_EVERY).zero?
          end
        end

        def flush
          path = File.join(@root, LEDGER_PATH)
          FileUtils.mkdir_p(File.dirname(path))
          line = JSON.generate(at: Time.now.utc.iso8601, total:, counts: snapshot)
          File.open(path, "a") { |io| io.write(line, "\n") }
        rescue StandardError => e
          # Cannot route through Swallow.log — it recurses into this stream.
          ::Kernel.warn("swallow_ledger: flush failed — #{e.class}: #{e.message}")
        end
      end
    end
  end
end
