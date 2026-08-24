# frozen_string_literal: true

require "fileutils"
require "json"

module Master
  module Trace
    module Log
      # Append-only tool invocation log; subscribes to tool:before on EventBus.
      class Audit
        LOG_PATH = ".master/audit.ndjson".freeze
        MAX_VAL = 120
        MAX_BYTES = 5 * 1024 * 1024

        def initialize(root:, event_bus:)
          @path = File.join(root, LOG_PATH)
          @mutex = Mutex.new
          FileUtils.mkdir_p(File.dirname(@path))
          event_bus.subscribe("tool:before") { |event_data| append(event_data) }
        end

        private

        def append(event_data)
          record = { ts: Time.now.utc.iso8601, tool: event_data[:tool] }
                    .merge(event_data.except(:tool).transform_values { |v| v.to_s[0, MAX_VAL] })
          Master::Trace::Telemetry.span("audit.append", tool: event_data[:tool].to_s) do
            @mutex.synchronize do
              rotate! if File.exist?(@path) && File.size(@path) > MAX_BYTES
              File.open(@path, "a") { |f| f.puts(JSON.generate(record)) }
            end
          end
        end

        def rotate!
          File.rename(@path, "#{@path}.1")
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "audit_log.rotate", path: @path)
        end
      end
    end
  end
end
