# frozen_string_literal: true

require "fileutils"

module Master
  # Append-only tool invocation log; subscribes to tool:before on EventBus.
  class AuditLog
    LOG_PATH  = ".master/audit.log".freeze
    MAX_VAL   = 120
    MAX_BYTES = 5 * 1024 * 1024

    def initialize(root:, event_bus:)
      @path  = File.join(root, LOG_PATH)
      @mutex = Mutex.new
      FileUtils.mkdir_p(File.dirname(@path))
      event_bus.subscribe("tool:before") { |event_data| append(event_data) }
    end

    private

    def append(event_data)
      payload_pairs = event_data.except(:tool)
                                .map { |k, v| "#{k}=#{v.to_s[0, MAX_VAL].inspect}" }
                                .join(" ")
      log_line = "#{Time.now.utc.iso8601} tool=#{event_data[:tool]} #{payload_pairs}"
      @mutex.synchronize do
        rotate! if File.exist?(@path) && File.size(@path) > MAX_BYTES
        File.open(@path, "a") { |f| f.puts(log_line) }
      end
    end

    def rotate!
      File.rename(@path, "#{@path}.1")
    rescue StandardError
      nil
    end
  end
end
