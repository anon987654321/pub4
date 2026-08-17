# frozen_string_literal: true

require "open3"
require_relative "../../trace/event_log"
require_relative "formatter"
require_relative "../resync_service"
require_relative "../fix_preview_report"

module Master
  module CLI
    module CommandRegistry
      module_function

      # /status — one-frame health panel. Replaces seven probing tool calls.
      def dispatch_status(root:, fix_loop:, bus:, git: Io::GitOperations.new(File.expand_path("..", root)), trace: nil, ctx: nil)
        data = gather_status_data(root:, fix_loop:, git:, trace:)
        render_status_lines(data).join("\n")
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
        lines
      end

      def last_event(root, pattern)
        Trace::EventLog.new(root:).recent(40, pattern:).last
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
        records = Trace::EventLog.new(root:).recent(40)
        records = records.select { |rec| rec["event"].to_s.match?(Trace::ReplayReader::FAILURE_PATTERN) }
        records.last(n).map { |rec| event_summary(rec, 2) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.failure_events")
        []
      end

      def recent_events(root, n)
        Trace::EventLog.new(root:).recent(n).map { |rec| event_summary(rec, 3) }.compact
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.recent_events")
        []
      end

      # /resync — divergence repair: tag, fetch, reset, bundle, restart.
      def dispatch_resync(root:, fix_loop:, git:, bus:, ctx: nil)
        ResyncService.new(root:, fix_loop:, git:, bus:).call(dry_run: arg_for(ctx).include?("--dry-run"))
      end

      # /tail [N] [pattern] — last N events matching pattern. Default N=20.
      def dispatch_tail(root:, ctx: nil)
        arg = arg_for(ctx)
        n_arg, pattern = arg.split(/\s+/, 2)
        n = n_arg.to_i.positive? ? n_arg.to_i : 20
        records = Trace::EventLog.new(root:).tail(n, pattern:)
        return "tail: no events" if records.empty?

        records.map do |rec|
          ts = rec["timestamp"].to_s.sub(/\..+/, "").sub("T", " ")
          "#{ts} #{rec["event"].ljust(28)} #{format_payload(rec["payload"])}"
        end.compact.join("\n")
      rescue StandardError => e
        "tail: #{e.message}"
      end

      def format_payload(pay)
        return pay.to_s[0, 100] unless pay.is_a?(Hash)

        Formatter.key_value_payload(pay)[0, 100]
      end

      def dispatch_fix(fix_loop:, root:, scanner: nil, ctx: nil, arg: nil)
        arg = arg || arg_for(ctx)
        sub, rest = arg.split(/\s+/, 2)
        case sub
        when "--dry-run" then preview_fix(fix_loop, rest, root, "fix dry-run")
        when "loop" then "fix loop: use /watch on for background watching"
        when "stop" then "fix stop: use /watch off for background watching"
        when "preview" then preview_fix(fix_loop, rest, root, "fix preview")
        else
          run_fix_and_prescan(fix_loop, scanner, arg, root)
        end
      end

      def preview_fix(fix_loop, rest, root, label)
        result = fix_loop.preview(expand_or_root(rest.to_s.strip, root))
        return "#{label}: #{result.message}" unless result.ok?

        FixPreviewReport.new(result.value!).render
      end

      def run_fix_and_prescan(fix_loop, scanner, arg, root)
        target = expand_or_root(arg, root)
        prescan = anti_sprawl_prescan(scanner:, target:, root:)
        result = fix_loop.run(target)
        output = result.ok? ? result.value! : fix_failure_with_alternatives(result.message, target)
        [prescan, output].reject(&:empty?).join("\n")
      end

      def anti_sprawl_prescan(scanner:, target:, root:)
        paths = prescan_paths(target)
        return "" if paths.empty?

        pairs = Master::Review::Scan::CrossFileAnalysis.new(root:).call(paths)
        findings = pairs.flat_map { |_path, result| Master::Result.wrap(result).value_or([]) }
        return "Checking for side effects...\nprescan: clean. Moving on." if findings.empty?

        lines = ["Checking for side effects...", "prescan: #{findings.size} cross-file risk(s) — Flat Hierarchy: merge/rename before local patch"]
        findings.first(8).each { |finding| lines << "  #{finding[:rule]}: #{finding[:message]}" }
        lines.join("\n")
      rescue StandardError => e
        scanner&.instance_variable_get(:@bus)&.publish("fix:prescan_error", path: target, error: e.message)
        "prescan: unavailable (#{e.class})"
      end

      def prescan_paths(target)
        path = target.to_s.empty? ? "." : target
        return [path] if File.file?(path)
        return [] unless File.directory?(path)

        Dir.glob(File.join(path, Master::Review::Scan::Scanner::SCAN_GLOB))
           .select { |entry| File.file?(entry) && !Master::Review::Scan::Scanner.skip_path?(entry, root: path) }
      end

      def fix_failure_with_alternatives(message, target)
        [
          "fix: #{message}",
          "alternatives:",
          "  1. /fix --dry-run #{target} to inspect intended changes without writing",
          "  2. /through --dry-run #{target} for the full preview pass",
          "  3. /through #{target} to scan, fix, and critique in one sequence",
        ].join("\n")
      end
    end
  end
end
