# frozen_string_literal: true

require "time"
require_relative "../../trace/log"

module Master
  module CLI
    module CommandRegistry
      module_function

      # /status — one-frame health panel. Replaces seven probing tool calls.
      def dispatch_status(root:, fix_loop:, bus:, git: Io::GitOperations.new(File.expand_path("..", root)), trace: nil,
                          learnings: nil, ctx: nil)
        gather_status_data(root:, fix_loop:, git:, trace:)
          .merge(rsi: rsi_opportunities(learnings))
          .then { |data| render_status_lines(data) }.join("\n")
      rescue StandardError => e
        "status: #{e.message}"
      end

      def gather_status_data(root:, fix_loop:, git:, trace:)
        stage_rec = last_event(root, "pipeline:stage_complete")
        verdict_rec = last_event(root, "review:verdict")
        {
          ahead_behind: git.ahead_behind,
          head: git.head || "?",
          dirty: git.dirty?("."),
          svc: service_status,
          bg: fix_loop&.background_alive? ? "running" : "stopped",
          af: ENV["MASTER_AUTOFIX"] == "1" ? "on" : "off",
          bndl: bundle_status(File.expand_path("..", root)),
          evts: recent_events(root, 5),
          failures: failure_events(root, 3),
          branch: git.branch || "?",
          turn_hint: trace&.last_turn ? "turn=#{trace.last_turn[:id]}" : "turn=none",
          stage_name: stage_rec&.dig("payload", "stage") || "none",
          verdict_line: format_verdict(verdict_rec),
          config: (Master::Ground::Config.new(root) rescue {}),
        }
      end

      def render_status_lines(d)
        ahead, behind = d[:ahead_behind]
        lines = [
          "status",
          "mode    #{Master::CLI::RuntimeMode.summary(config: d[:config])}",
          "service master/#{d[:svc][:state]} #{d[:svc][:detail]}",
          "git     #{d[:branch]}@#{d[:head]} ahead=#{ahead} behind=#{behind} #{d[:dirty] ? "dirty" : "clean"}",
          "fix     bg=#{d[:bg]} autofix=#{d[:af]}",
          "bundle  #{d[:bndl]}",
          "trace   #{d[:turn_hint]}",
          "pipeline last=#{d[:stage_name]} #{d[:verdict_line]}",
          "events  (last #{d[:evts].size})",
        ]
        d[:evts].each { |e| lines << "  #{e[:ago]} #{e[:event]} #{e[:summary]}" }
        d[:failures].each { |e| lines << "  !#{e[:ago]} #{e[:event]} #{e[:summary]}" }
        Array(d[:rsi]).each { |row| lines << "rsi     #{format_opportunity(row)}" }
        lines
      end

      # The feedback ledger's reading of the last week: a tool failing a fifth
      # of its calls, a correction or a provider error that keeps recurring.
      def rsi_opportunities(learnings)
        learnings.respond_to?(:opportunities) ? learnings.opportunities : []
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.rsi_opportunities")
        []
      end

      def format_opportunity(row)
        return "#{row[:category]} #{row[:dimension]} x#{row[:count]}" unless row[:fail_rate]

        "#{row[:category]} #{row[:dimension]} #{(row[:fail_rate] * 100).round}% of #{row[:total]}"
      end

      def last_event(root, pattern)
        Trace::Log::Event.new(root:).recent(40, pattern:).last
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.last_event")
        nil
      end

      def format_verdict(rec)
        return "" unless rec

        pay = rec["payload"]
        return "" unless pay.is_a?(Hash)

        pass = pay["pass"] ? "pass" : "fail"
        score = pay["score"]
        score ? "review=#{pass} score=#{score}" : "review=#{pass}"
      end

      def service_status
        out, _, st = Master::Io::Exec.capture3("/usr/sbin/rcctl", "check", "master")
        { state: st.success? ? "ok" : "down", detail: out.strip }
      rescue Errno::ENOENT
        { state: "n/a", detail: "rcctl absent — not OpenBSD" }
      rescue StandardError => e
        { state: "?", detail: "rcctl err: #{e.class}: #{e.message[0, 60]}" }
      end

      def bundle_ok?(dir)
        out, = Master::Io::Exec.capture2e("bundle34", "check", chdir: dir)
        out.match?(/dependencies.*satisfied/)
      end

      def bundle_status(repo)
        mas_ok = bundle_ok?(File.join(repo, "MASTER"))
        web_ok = bundle_ok?(File.join(repo, "MASTER/web"))
        mas_ok && web_ok ? "ok (MASTER+web satisfied)" : "drift — run bundle install"
      rescue StandardError => e
        "unknown (#{e.class})"
      end

      def format_ago(secs)
        return "#{secs}s" if secs < 60

        secs < 3600 ? "#{secs / 60}m" : "#{secs / 3600}h"
      end

      def event_summary(rec, key_count)
        pay = rec["payload"]
        sum = pay.is_a?(Hash) ? pay.first(key_count).map { |k, v| "#{k}=#{v.to_s.tr('"', "")[0, 24]}" }.join(" ") : pay.to_s
        now = Time.now.utc
        ts = (Time.parse(rec["timestamp"]) rescue now)
        { ago: format_ago((now - ts).to_i.abs).rjust(4), event: rec["event"].to_s, summary: sum[0, 80] }
      end

      def failure_events(root, n)
        records = Trace::Log::Event.new(root:).recent(40)
        records = records.select { |rec| rec["event"].to_s.match?(Trace::ReplayReader::FAILURE_PATTERN) }
        records.last(n).map { |rec| event_summary(rec, 2) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.failure_events")
        []
      end

      def recent_events(root, n)
        Trace::Log::Event.new(root:).recent(n).map { |rec| event_summary(rec, 3) }.compact
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.recent_events")
        []
      end
    end
  end
end
