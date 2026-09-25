# frozen_string_literal: true

require "time"
require_relative "../../trace/log"

module Master
  module CLI
    module CommandRegistry
      module_function

      # /status — one frame of health, as dmesg lines. What is fine or does not
      # apply on this host says nothing: no "rcctl absent" on a Mac, no bundle row
      # when the bundle is satisfied, no raw bus events.
      #
      # `/status mission` and `/status runtime` read the two durable records a
      # frame does not show: the autonomous mission, and the known-good commit.
      def dispatch_status(root:, fix_loop:, bus:, git: Io::GitOperations.new(File.expand_path("..", root)), trace: nil,
                          learnings: nil, ctx: nil)
        word, rest = subcommand(ctx)
        return dispatch_mission(root, ctx: rest) if word == "mission"
        return dispatch_runtime(root, ctx: rest) if word == "runtime"

        gather_status_data(root:, fix_loop:, git:)
          .merge(rsi: rsi_opportunities(learnings))
          .then { |data| render_status_lines(data) }.join("\n")
      rescue StandardError => e
        "status0: #{e.message}"
      end

      def gather_status_data(root:, fix_loop:, git:)
        {
          ahead_behind: git.ahead_behind, head: git.head || "?", dirty: git.dirty?("."), branch: git.branch || "?",
          svc: service_status,
          bg: fix_loop&.background_alive? ? "running" : "stopped",
          af: ENV["MASTER_AUTOFIX"] == "1" ? "on" : "off",
          bndl: bundle_status(File.expand_path("..", root)),
          failures: failure_events(root, 3),
          stage: last_event(root, "pipeline:stage_complete")&.dig("payload", "stage"),
          verdict: format_verdict(last_event(root, "review:verdict")),
          config: (Master::Ground::Config.new(root) rescue {})
        }
      end

      def render_status_lines(d)
        lines = ["master0: #{Master::CLI::RuntimeMode.summary(config: d[:config])}", git_line(d)]
        lines << "service0: master #{d[:svc][:state]}" if d.dig(:svc, :state)
        lines << "fix0: background #{d[:bg]}, autofix #{d[:af]}" if d[:bg]
        lines << "review0: last stage #{d[:stage]}#{d[:verdict]}" if d[:stage]
        lines << "bundle0: #{d[:bndl]}" if d[:bndl]
        Array(d[:failures]).each { |e| lines << "trace0: #{e}" }
        Array(d[:rsi]).each { |row| lines << "learn0: #{format_opportunity(row)}" }
        lines.compact
      end

      def git_line(d)
        ahead, behind = d[:ahead_behind]
        counts = [("#{ahead} ahead" if ahead.to_i.positive?), ("#{behind} behind" if behind.to_i.positive?)]
        return unless d[:branch]

        ["git0: #{d[:branch]} at #{d[:head]}", *counts.compact, d[:dirty] ? "dirty" : "clean"].join(", ")
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
        kind = row[:category].to_s.tr("_", " ")
        return "#{row[:dimension]}, #{row[:count]} #{kind}" unless row[:fail_rate]

        "#{row[:dimension]} failed #{(row[:fail_rate] * 100).round}% of #{row[:total]} calls"
      end

      def last_event(root, pattern)
        Trace::Log::Event.new(root:).recent(40, pattern:).last
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.last_event")
        nil
      end

      def format_verdict(rec)
        pay = rec && rec["payload"]
        return "" unless pay.is_a?(Hash)

        ", review #{pay["pass"] ? "pass" : "fail"}#{", score #{pay["score"]}" if pay["score"]}"
      end

      RCCTL = "/usr/sbin/rcctl"

      # Only a host with rcctl has a master service to report.
      def service_status
        return {} unless File.executable?(RCCTL)

        _, _, st = Master::Io::Exec.capture3(RCCTL, "check", "master")
        { state: st.success? ? "ok" : "down" }
      rescue StandardError => e
        { state: "unknown, #{e.class}" }
      end

      # Silent when satisfied, and where bundle34 does not exist.
      def bundle_status(repo)
        drift = %w[MASTER MASTER/web].reject do |dir|
          out, = Master::Io::Exec.capture2e("bundle34", "check", chdir: File.join(repo, dir))
          out.match?(/dependencies.*satisfied/)
        end
        "#{drift.join(", ")} drift, run bundle install" unless drift.empty?
      rescue Errno::ENOENT
        nil
      end

      def format_ago(secs)
        return "#{secs}s" if secs < 60

        secs < 3600 ? "#{secs / 60}m" : "#{secs / 3600}h"
      end

      # "tool:failed 4m ago: timeout", the event and what it said.
      def failure_events(root, n)
        records = Trace::Log::Event.new(root:).recent(40)
        records.select { |rec| rec["event"].to_s.match?(Trace::ReplayReader::FAILURE_PATTERN) }.last(n).map do |rec|
          said = rec["payload"].is_a?(Hash) ? rec["payload"].values_at("error", "message").compact.first : nil
          ago = format_ago((Time.now.utc - (Time.parse(rec["timestamp"]) rescue Time.now.utc)).to_i.abs)
          "#{rec["event"]} #{ago} ago#{": #{said.to_s[0, 80]}" if said}"
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.failure_events")
        []
      end
    end
  end
end
