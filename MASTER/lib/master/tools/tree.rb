# frozen_string_literal: true

require "open3"

module Master
  module Tools
    # Tree — lists directory structure using sh/tree.sh.
    # Safe: read-only, no writes.
    class Tree
      SCRIPT = File.expand_path("../../../sh/tree.sh", __dir__).freeze

      def initialize(root:, event_bus: nil)
        @bus = event_bus
        @root = root
      end

      def call(path: nil)
        target = path ? File.expand_path(path, @root) : @root
        return Result.err("path not found: #{target}", category: :validation) unless Dir.exist?(target)

        out, err, status = Open3.capture3("zsh", SCRIPT, target)
        return Result.err("tree failed: #{err.strip}", category: :unknown) unless status.success?

        lines = out.lines.map(&:chomp).reject(&:empty?)
        @bus&.publish("tool:tree", path: target, count: lines.size)
        Result.ok(lines.join("\n"))
      rescue StandardError => e
        Result.err("tree: #{e.message}", category: :unknown)
      end
    end
  end
end
