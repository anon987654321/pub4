# frozen_string_literal: true

require "fileutils"
require_relative "../trace/hooks"

module Master
  module Plugins
    module Trace
      RING_SIZE = 1000

      def self.boot(root:, config:)
        event_log = Master::Trace::EventLog.new(root:)
        bus       = Master::Trace::EventBus.new(event_log:)
        ring      = Master::Trace::RingBuffer.new(RING_SIZE)
        logging   = Master::Trace::Logging.new(ring_buffer: ring, event_bus: bus)
        session   = Master::Trace::Session.new(root:, budget_max: config.budget_max, req_max: config.req_max)
        undo      = Master::Trace::Undo.new(session:, event_bus: bus, root:)
        metrics   = Master::Trace::Metrics.new(root:, event_bus: bus)
        Master::Trace::AuditLog.new(root:, event_bus: bus)
        Master::Trace::SwallowLedger.new(event_bus: bus, root:).attach
        Master::Trace::Hooks.new(root: root, event_bus: bus, budget_max: config.budget_max).attach
        recorder  = Master::Trace::Recorder.new(root:, event_bus: bus)
        { event_log:, bus:, ring:, logging:, session:, undo:, metrics:, trace: recorder }
      end

      SNAPSHOT_MAX_BYTES = 50_000
      SNAPSHOT_DIRS      = %w[bin lib data].freeze

      def self.boot_snapshot(container)
        root  = container[:root]
        files = Dir[*SNAPSHOT_DIRS.map { |d| File.join(root, d, "**", "*") }]
                  .select { |f| File.file?(f) && File.size(f) < SNAPSHOT_MAX_BYTES }
                  .reject { |f| f.include?("/knowledge/") || f.include?("/vendor/") }
                  .sort
        body  = files.flat_map do |f|
          rel  = f.delete_prefix("#{root}/")
          lang = Master::FILE_LANGUAGE_MAP.fetch(File.extname(f).downcase, "text")
          src  = File.read(f, encoding: "UTF-8", invalid: :replace)
          ["## #{rel}", "```#{lang}", src.rstrip, "```", ""]
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "plugins.trace.snapshot_file", path: f)
          []
        end
        header  = ["# MASTER Snapshot", "Generated: #{Time.now.utc.iso8601}", "Files: #{files.size}", ""]
        root_snapshots = snapshot_artifacts(root)
        content = (header + root_snapshots + body).join("\n")
        out     = File.join(root, ".master", "snapshot.md")
        FileUtils.mkdir_p(File.dirname(out))
        File.write(out, content)
        File.write(File.join(root, "snapshot.md"), content)
        container[:bus]&.publish("boot:snapshot", files: files.size)
      rescue StandardError => e
        container[:bus]&.publish("boot:snapshot_error", error: e.message)
      end

      def self.snapshot_artifacts(root)
        paths = %w[MASTER_snapshot.md DEPLOY_snapshot.md].filter_map do |name|
          path = File.join(root, name)
          next unless File.file?(path)
          "- `#{name}` (#{File.size(path)} bytes, updated #{Time.at(File.mtime(path).to_i).utc.iso8601})"
        end
        return [] if paths.empty?

        ["## Root snapshot artifacts", *paths, ""]
      end

      Master::Plugin.register(:trace, self)
    end
  end
end
