# frozen_string_literal: true

module Master
  module Fix
    # The SCAN phase boundary owned by /fix. Detection remains a separate
    # mechanism; Fix owns when it runs, what evidence enters the repair loop,
    # and whether a failed measurement can be trusted.
    class ScanPhase
      def initialize(scanner:, root:, bus: nil)
        @scanner = scanner
        @root = File.expand_path(root)
        @bus = bus
      end

      def full_semantic!
        @scanner.full_semantic! if @scanner.respond_to?(:full_semantic!)
        self
      end

      def semantic_full?
        @scanner.respond_to?(:semantic_full?) && @scanner.semantic_full?
      end

      def call(path, depth: :deep)
        relative = path.to_s.delete_prefix("#{@root}/")
        @bus&.publish("fix:phase", phase: "scan", file: relative)
        Master::Result.wrap(@scanner.scan(path, depth:))
      rescue StandardError => e
        @bus&.publish("fix:phase_error", phase: "scan", file: relative, error: e.message)
        Master::Result.err("fix scan failed for #{relative}: #{e.class}: #{e.message}", category: :infrastructure)
      end
    end
  end
end
