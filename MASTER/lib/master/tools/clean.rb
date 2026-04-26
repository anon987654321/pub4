# frozen_string_literal: true

require "open3"
require "pathname"

module Master
  module Tools
    # Clean — removes trailing whitespace, CRLF, and excess blank lines
    # from text files under a given path, using sh/clean.sh.
    class Clean
      SCRIPT = Pathname.new(__dir__).join("../../../sh/clean.sh").expand_path.freeze

      def initialize(root:, governor:, event_bus: nil)
        @bus = event_bus
        @root = Pathname.new(root)
        @governor = governor
      end

      def call(path: nil)
        target = (path ? @root.join(path) : @root).expand_path.to_s
        return Result.err("path not found: #{target}", category: :validation) unless File.exist?(target)

        guard = @governor.guard("clean #{target}")
        return Result.err(guard.message, category: :policy) if guard.respond_to?(:ok?) && !guard.ok?

        out, err, status = Open3.capture3("zsh", SCRIPT.to_s, target)
        return Result.err("clean failed: #{err.strip}", category: :unknown) unless status.success?

        cleaned = out.each_line.map { |l| l.delete_prefix("Cleaned: ").chomp if l.start_with?("Cleaned:") }.compact
        @bus&.publish("tool:clean", path: target, count: cleaned.size)
        Result.ok("cleaned #{cleaned.size} file(s):\n#{cleaned.join("\n")}")
      rescue StandardError => e
        Result.err("clean: #{e.message}", category: :unknown)
      end
    end
  end
end
EOF