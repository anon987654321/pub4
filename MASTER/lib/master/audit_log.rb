# frozen_string_literal: true

require "fileutils"

module Master
  # Append-only audit trail of every tool invocation.
  # Subscribes to tool:before events on the shared EventBus.
  # Written to data/audit.log — one line per call, machine-readable.
  class AuditLog
    LOG_PATH = "data/audit.log"
    MAX_VAL  = 120

    def initialize(root:, event_bus:)
      @path  = File.join(root, LOG_PATH)
      FileUtils.mkdir_p(File.dirname(@path))
      event_bus.subscribe("tool:before") { |ev| append(ev) }
    end

    private

    def append(ev)
      pairs = ev.reject { |k, _| k == :tool }
                .map    { |k, v| "#{k}=#{v.to_s[0, MAX_VAL].inspect}" }
                .join(" ")
      line = "#{Time.now.utc.iso8601} tool=#{ev[:tool]} #{pairs}"
      File.open(@path, "a") { |f| f.puts(line) }
    rescue StandardError
      nil
    end
  end
end
