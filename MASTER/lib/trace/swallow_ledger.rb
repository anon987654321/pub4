# frozen_string_literal: true

module Master
  module Trace
    # Ground::Swallow.log makes a tolerated failure *visible* by publishing a
    # `swallow:error` event. Visible is not the same as observed — without a
    # listener those events scroll past and vanish.
    #
    # SwallowLedger subscribes once at boot and tallies every swallow by its
    # `context:` tag, appending a periodic snapshot to
    # runtime/swallow_ledger.jsonl. A swallow that fires twice a day is noise;
    # the same context firing 400 times an hour is a defect wearing a
    # tolerated-failure costume. The ledger is what tells the two apart.
    #
    # Wire once: SwallowLedger.new(event_bus: bus, root: root).attach
    class SwallowLedger
      LEDGER_PATH      = "runtime/swallow_ledger.jsonl"
      SNAPSHOT_EVERY   = 50  # flush a snapshot line every N swallows

      def initialize(event_bus:, root: Master::ROOT)
        @bus     = event_bus
        @root    = root
        @counts  = Hash.new(0)
        @total   = 0
        @mutex   = Mutex.new
      end

      # Subscribe to the swallow stream. Idempotent-friendly: call once.
      def attach
        return self unless @bus

        @bus.subscribe("swallow:error") do |payload|
          record(payload)
        end
        self
      end

      # Current tally — context => count. Useful for /axioms and tests.
      def snapshot
        @mutex.synchronize { @counts.dup }
      end

      def total
        @mutex.synchronize { @total }
      end

      private

      def record(payload)
        context = payload[:context] || payload["context"] || "unknown"
        flush_due = false

        @mutex.synchronize do
          @counts[context] += 1
          @total += 1
          flush_due = (@total % SNAPSHOT_EVERY).zero?
        end

        flush if flush_due
      end

      def flush
        path = File.join(@root, LEDGER_PATH)
        FileUtils.mkdir_p(File.dirname(path))
        line = JSON.generate(
          at:     Time.now.utc.iso8601,
          total:  total,
          counts: snapshot
        )
        File.open(path, "a") { |io| io.write(line, "\n") }
      rescue StandardError => e
        # The ledger's own write failed. It cannot route through Swallow.log
        # without recursing into the very stream it observes — stderr only.
        Kernel.warn("swallow_ledger: flush failed — #{e.class}: #{e.message}")
      end
    end
  end
end
