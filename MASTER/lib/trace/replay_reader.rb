# frozen_string_literal: true

require "json"
require "open3"
require "time"

module Master
  module Trace
    class ReplayReader
      FAILURE_PATTERN = /error|fail|violation|veto|timeout|rollback/i

      def initialize(root: Master::ROOT, recorder: nil)
        @root = root
        @recorder = recorder
        @event_log = Log::Event.new(root:)
      end

      def render(arg: "")
        mode, rest = parse_arg(arg)
        case mode
        when :turn
          render_turn
        when :failures
          render_events(limit: rest.to_i.positive? ? rest.to_i : 15, failures_only: true)
        when :date
          render_trace_date(rest)
        when :commit
          render_commit(rest)
        when :evidence
          render_evidence(limit: rest.to_i.positive? ? rest.to_i : 20)
        else
          render_events(limit: mode.is_a?(Integer) ? mode : 20)
        end
      end

      private

      def parse_arg(arg)
        tokens = arg.to_s.strip.split(/\s+/, 2)
        head = tokens.first.to_s.downcase
        tail = tokens[1].to_s
        case head
        when "", "activity" then [:activity, tail]
        when "turn" then [:turn, tail]
        when "failures" then [:failures, tail]
        when "commit" then [:commit, tail]
        when "evidence" then [:evidence, tail]
        when /\A\d+\z/ then [head.to_i, tail]
        when /\A\d{4}-\d{2}-\d{2}\z/ then [:date, head]
        else [:activity, arg.to_s]
        end
      end

      def render_events(limit:, failures_only: false)
        records = @event_log.recent(limit * 3)
        records = records.select { |rec| rec["event"].to_s.match?(FAILURE_PATTERN) } if failures_only
        records = records.last(limit)
        return "replay: no #{failures_only ? "failure " : ""}events" if records.empty?

        lines = ["replay activity (#{records.size})"]
        records.each { |rec| lines << format_record(rec) }
        lines.join("\n")
      end

      def render_turn
        turn = @recorder&.last_turn
        turn ||= load_last_turn_from_disk
        return @recorder.pretty_last if turn.nil? && @recorder
        return "replay: no turn trace recorded" unless turn

        lines = ["replay turn #{turn[:id]}", "  channel=#{turn[:channel]}  message=#{turn.fetch(:message, "")[0, 80]}"]
        Array(turn[:events]).each do |ev|
          ms = ev[:ts_ms] || ev["ts_ms"]
          name = ev[:event] || ev["event"]
          detail = (ev.is_a?(Hash) ? ev : {}).except(:ts_ms, :event, "ts_ms", "event").reject { |_, v| v.nil? }
          lines << "  +#{ms.to_s.rjust(5)}ms  #{name}  #{detail.empty? ? "" : detail.inspect}"
        end
        lines.join("\n")
      end

      def render_trace_date(date)
        path = File.join(@root, "data", "traces", "#{date}.jsonl")
        return "replay: no trace file for #{date}" unless File.file?(path)

        lines = ["replay traces #{date}"]
        File.foreach(path).each_with_index do |line, index|
          turn = JSON.parse(line, symbolize_names: true)
          lines << "turn #{index + 1}: #{turn[:id]} #{turn[:message].to_s[0, 60]}"
        end
        lines.join("\n")
      rescue JSON::ParserError => e
        "replay: corrupt trace file (#{e.message})"
      end

      def format_record(rec)
        ts = (Time.parse(rec["timestamp"]) rescue Time.now.utc).strftime("%H:%M:%S")
        event = rec["event"].to_s.ljust(28)
        pay = rec["payload"]
        summary = pay.is_a?(Hash) ? pay.first(4).map { |k, v| "#{k}=#{v.to_s.tr('"', "")[0, 24]}" }.join(" ") : pay.to_s
        "#{ts} #{event} #{summary[0, 100]}"
      end

      def render_commit(sha)
        sha = sha.to_s.strip
        return "replay: usage: /replay commit <sha>" if sha.empty?

        info = commit_info(sha)
        return info if info.is_a?(String)

        window = 300
        events = nearby_events(info[:time], window:)
        lines = [
          "replay commit #{info[:short]} #{info[:subject]}",
          "  author=#{info[:author]} at=#{info[:time].utc.iso8601}",
          "  events ±#{window}s (#{events.size})",
        ]
        events.each { |rec| lines << "  #{format_record(rec)}" }
        lines.join("\n")
      end

      def render_evidence(limit:)
        log = Log::Evidence.new(root: @root)
        records = log.recent(limit)
        return "replay: no evidence events" if records.empty?

        lines = ["replay evidence (#{records.size})"]
        records.each { |rec| lines << format_record(rec) }
        lines.join("\n")
      end

      def commit_info(sha)
        repo = File.expand_path("..", @root)
        out, _, status = Master::Io::Exec.capture3(
          "git", "-C", repo, "show", "-s", "--format=%H|%h|%an|%aI|%s", sha
        )
        return "replay: commit not found: #{sha}" unless status.success? && !out.strip.empty?

        full, short, author, at, subject = out.strip.split("|", 5)
        { full:, short:, author:, time: Time.parse(at), subject: subject.to_s }
      rescue StandardError => e
        "replay: commit lookup failed (#{e.message})"
      end

      def nearby_events(center, window:)
        start_at = center - window
        end_at = center + window
        @event_log.recent(500).select do |rec|
          ts = (Time.parse(rec["timestamp"]) rescue nil)
          ts && ts >= start_at && ts <= end_at
        end
      end

      def load_last_turn_from_disk
        dir = File.join(@root, "data", "traces")
        files = Dir.glob(File.join(dir, "*.jsonl")).sort
        return if files.empty?

        last_line = nil
        File.foreach(files.last) { |line| last_line = line }
        last_line ? JSON.parse(last_line, symbolize_names: true) : nil
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplayReader.load_last_turn_from_disk")
        nil
      end
    end
  end
end
