# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Trace
  # Trace — captures all bus events for the current turn into a JSONL log
  # at .master/traces/YYYY-MM-DD.jsonl (local state, never data/ — a runtime
  # write target inside the law tree read as config). One turn record per line.
  # /why formats the last turn.
    class Recorder
      EVENT_PATTERNS = %w[gateway:* pipeline:* tool:after route:* council:* memo:* lint:* governor:*].freeze
      MAX_EVENTS_PER_TURN = 200

      def initialize(root:, event_bus:)
        @dir = File.join(root, ".master", "traces")
        @bus = event_bus
        @mutex = Mutex.new
        @current = nil
        @last = nil
        FileUtils.mkdir_p(@dir)
        subscribe
      end

      def last_turn = @last

      def pretty_last
        turn = @last || load_last_from_disk
        return "no trace recorded yet" unless turn

        lines = ["turn #{turn[:id]}  ts=#{turn[:start_ts]}  channel=#{turn[:channel]}"]
        lines << "  message: #{(turn.fetch(:message, ""))[0, 100]}"
        turn[:events].each do |ev|
          ms = ev[:ts_ms]
          name = ev[:event]
          detail = ev.except(:ts_ms, :event).reject { |_, v| v.nil? }
          lines << "  +#{ms.to_s.rjust(5)}ms  #{name}  #{detail.empty? ? "" : detail.inspect}"
        end
        lines.join("\n")
      end

      private

      def subscribe
        EVENT_PATTERNS.each { |pat| @bus.subscribe(pat) { |ev| record(ev) } }
      end

      def record(event)
        @mutex.synchronize do
          if event[:event] == "gateway:turn_start"
            @current = { id: event[:turn_id], start_ts: Time.now.to_i, channel: event[:channel],
                         message: event[:message], events: [], t0: event[:ts] }
            next
          end
          if @current && event[:event] == "gateway:turn_done"
            @current[:events] << relative(event)
            finalize(@current)
            @last = @current
            @current = nil
            next
          end
          next unless @current
          next if @current[:events].size >= MAX_EVENTS_PER_TURN
          @current[:events] << relative(event)
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.ingest")
      end

      def relative(ev)
        ts0 = @current.fetch(:t0, 0)
        ev.merge(ts_ms: (ev.fetch(:ts, 0)) - ts0).except(:ts)
      end

      def finalize(turn)
        path = File.join(@dir, "#{Time.now.strftime("%Y-%m-%d")}.jsonl")
        File.open(path, "a") { |f| f.puts JSON.generate(turn) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.finalize", path:)
      end

      def load_last_from_disk
        files = Dir.glob(File.join(@dir, "*.jsonl")).sort
        return if files.empty?
        File.foreach(files.last) { |l| last_line = l }
        last_line ? JSON.parse(last_line, symbolize_names: true) : nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "recorder.load_last_from_disk")
        nil
      end
    end
  end
end
