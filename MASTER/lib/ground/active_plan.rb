# frozen_string_literal: true

require "fileutils"
require_relative "../io/atomic_write"

module Master
  module Ground
    # Pinned stepwise plan re-read each turn (opencrabs v0.3.43 plan pinning).
    module ActivePlan
      include Master::Io::AtomicWrite
      extend Master::Io::AtomicWrite
      MAX_BYTES = 4_096
      REL_PATH = "runtime/active_plan.md".freeze

      module_function

      def path(root) = File.join(root, REL_PATH)

      def read(root)
        file = path(root)
        return unless File.file?(file)

        body = File.read(file, encoding: "UTF-8").strip
        body.empty? ? nil : body
      end

      def pin(root, text, bus: nil)
        body = text.to_s.strip
        return clear(root, bus:) if body.empty?

        body = body.byteslice(0, MAX_BYTES)
        FileUtils.mkdir_p(File.dirname(path(root)))
        write_atomic(path(root), "#{body}\n", mode: 0o600)
        bus&.publish("plan:pinned", bytes: body.bytesize)
        body
      end

      def clear(root, bus: nil)
        file = path(root)
        File.delete(file) if File.exist?(file)
        bus&.publish("plan:cleared")
        nil
      end

      def attach(bus, root)
        bus.subscribe("propose_tree:done") do
          proposals = File.join(root, "runtime", "proposals.md")
          next unless File.file?(proposals)

          pin(root, File.read(proposals)[0, MAX_BYTES], bus:)
        rescue StandardError => e
          bus.publish("plan:pin_error", error: e.message)
        end
      end

      def prompt_section(root)
        body = read(root)
        return unless body

        "## Active plan (pinned)\n#{body}"
      end
    end
  end
end
