# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Review
    module Scan
      module ProgressReporter
        private

        def reset_scan_progress(total, unit: nil)
          @scan_unit_seq = (@scan_unit_seq || -1) + 1
          name = unit || @through_scan_unit || "scan#{@scan_unit_seq}"
          @scan_progress = {
            total:,
            done: 0,
            violations: 0,
            dirty_files: 0,
            rules: Hash.new(0),
            unit: name,
            started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC),
          }
          $stdout.sync = true
          Master::Trace::Dmesg.attach(name, "mainbus0", "files=#{total} stream=on")
        end

        def emit_scan_progress(dir:, path:, file_result:)
          return unless @scan_progress

          findings = file_result.ok? ? Array(file_result.value!) : []
          count = findings.size
          rel = path.sub(dir, "").delete_prefix("/")
          rule_hits = findings.filter_map { |f| finding_rule_id(f) }

          done, total, viol_total, dirty, top = update_scan_progress_state(count, rule_hits)

          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @scan_progress[:started_at]
          eta_s = done.positive? ? ((elapsed / done) * (total - done)).round : nil
          unit = @scan_progress[:unit] || "scan0"

          log_scan_hit(unit:, done:, total:, rel:, count:, eta_s:)
          append_scan_hits_jsonl(path, findings)
          log_scan_checkpoint(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
          log_scan_completion(unit:, done:, total:, viol_total:, dirty:, elapsed:) if done == total
          @bus&.publish("scan:progress", done:, total:, path: rel, violations: count, eta_s:, top: top.to_h)
        end

        # One line per finding, appended as the file is judged, so a 16-hour
        # walk is not a list you have to relocate afterwards.
        def append_scan_hits_jsonl(path, findings)
          return if findings.empty?

          file = File.join(Master::ROOT, ".master", "scan_hits.jsonl")
          FileUtils.mkdir_p(File.dirname(file))
          File.open(file, "a") do |io|
            findings.each do |finding|
              io.puts({
                path: path.to_s,
                line: finding_line(finding),
                rule: finding_rule_id(finding),
                message: finding_message(finding),
              }.to_json)
            end
          end
        rescue StandardError
          nil
        end

        def finding_line(finding)
          return finding.line if finding.respond_to?(:line)
          return finding[:line] if finding.respond_to?(:[])

          nil
        end

        def finding_message(finding)
          return finding.message if finding.respond_to?(:message)
          return finding[:message] if finding.respond_to?(:[])

          nil
        end

        def update_scan_progress_state(count, rule_hits)
          @mutex.synchronize do
            sp = @scan_progress
            sp[:done] += 1
            sp[:violations] = sp[:violations].to_i + count
            sp[:dirty_files] = sp[:dirty_files].to_i + 1 if count.positive?
            tally_rule_hits(sp, rule_hits)
            [sp[:done], sp[:total], sp[:violations], sp[:dirty_files], sp[:rules].sort_by { |_, n| -n }.first(6)]
          end
        end

        def tally_rule_hits(sp, rule_hits)
          rule_hits.each { |rid| sp[:rules][rid.upcase] += 1 }
        end

        def log_scan_hit(unit:, done:, total:, rel:, count:, eta_s:)
          return unless count.positive?

          Master::Trace::Dmesg.status(
            unit,
            "hit #{done}/#{total} #{rel} +#{count}" \
            "#{eta_s&.positive? ? " eta=#{eta_s}s" : ""}",
          )
        end

        def log_scan_checkpoint(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
          step = checkpoint_step(total)
          return unless done == total || (done % step).zero?

          top_s = top.map { |rule, n| "#{rule}=#{n}" }.join(" ")
          Master::Trace::Dmesg.status(
            unit,
            "checkpoint #{done}/#{total} violations=#{viol_total} dirty_files=#{dirty}" \
            "#{eta_s&.positive? ? " eta=#{eta_s}s" : ""}" \
            " elapsed=#{elapsed.round}s" \
            "#{top_s.empty? ? "" : " top #{top_s}"}",
          )
          write_progress_snapshot(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
        end

        # An operator reads this line as the verdict, so a tier that could
        # not run has to appear on it. Without `skipped`, a scan where a
        # provider spend limit silently removed the whole semantic tier
        # prints the same "complete=yes violations=0" as a scan that
        # actually looked.
        def log_scan_completion(unit:, done:, total:, viol_total:, dirty:, elapsed:)
          fields = {
            complete: true, files: total, violations: viol_total,
            dirty_files: dirty, elapsed_s: elapsed.round,
          }
          skipped = Master::Ground::QuotaGate.report
          fields[:skipped] = skipped if skipped
          Master::Trace::Dmesg.kv(unit, **fields)
        end

        def checkpoint_step(total)
          return 1 if total <= 10
          return 5 if total <= 50
          return 10 if total <= 100

          [25, (total / 10.0).ceil].max
        end

        def write_progress_snapshot(unit:, done:, total:, viol_total:, dirty:, elapsed:, top: [], eta_s: nil)
          root = defined?(Master::ROOT) ? Master::ROOT : Dir.pwd
          top_s = top.map { |rule, n| "#{rule}=#{n}" }.join(" ")
          text = [
            "phase: streaming #{unit}",
            "progress: #{done}/#{total} files",
            "violations: #{viol_total} dirty_files=#{dirty}",
            "elapsed_s: #{elapsed.round} eta_s: #{eta_s || "-"}",
            ("top: #{top_s}" unless top_s.empty?),
            "note: partial — full report lands after pass completes",
          ].compact.join("\n")
          # Quiet write — checkpoints already print top rules; avoid spam.
          if defined?(Master::CLI::ScanLive)
            Master::CLI::ScanLive.snapshot!(text, root:, note: "streaming checkpoint", announce: false)
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Scanner.write_progress_snapshot")
        end

        def finding_rule_id(finding)
          return finding.rule.to_s if finding.respond_to?(:rule)
          return finding[:rule].to_s if finding.respond_to?(:[]) && finding[:rule]

          nil
        end
      end
    end
  end
end
