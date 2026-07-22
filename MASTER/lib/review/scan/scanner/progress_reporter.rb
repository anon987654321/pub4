# frozen_string_literal: true

module Master
  module Review
    module Scan
      class Scanner
        # Live scan progress: dmesg-style streaming status lines, checkpoint
        # snapshots, and completion events. Grouped apart from the core
        # scan/parallelism logic to keep Scanner itself under NO_GOD_CLASS's
        # 300-line ceiling -- a real separation (reporting vs scanning), not
        # just metric evasion; mixed-in modules live in their own ModuleNode
        # so this doesn't count against the including class's own span.
        module ProgressReporter
          private

          def reset_scan_progress(total, unit: nil)
            @scan_unit_seq = (@scan_unit_seq || -1) + 1
            name = unit || @through_scan_unit || "scan#{@scan_unit_seq}"
            @scan_progress = {
              total: total,
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
            log_scan_checkpoint(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
            log_scan_completion(unit:, done:, total:, viol_total:, dirty:, elapsed:) if done == total
            @bus&.publish("scan:progress", done:, total:, path: rel, violations: count, eta_s:, top: top.to_h)
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

          # Canonical RuleDSL ids are uppercase, but some findings arrive with
          # a lowercase label (e.g. principle_map.yml's "detects:" taxonomy)
          # for the same underlying category -- tallying both casings
          # separately split one violation count into two lines in the live
          # "top=" summary (e.g. "long_line=440,LONG_LINE=440"). Normalize so
          # every distinct violation category earns exactly one slot.
          def tally_rule_hits(sp, rule_hits)
            rule_hits.each { |rid| sp[:rules][rid.upcase] += 1 }
          end

          # Per-file: only dirty files (signal), not clean-file spam.
          def log_scan_hit(unit:, done:, total:, rel:, count:, eta_s:)
            return unless count.positive?

            Master::Trace::Dmesg.status(
              unit,
              "hit #{done}/#{total} #{rel} +#{count}" \
              "#{eta_s && eta_s.positive? ? " eta=#{eta_s}s" : ""}"
            )
          end

          # Decision-grade checkpoints: progress + top rules so far.
          def log_scan_checkpoint(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
            step = checkpoint_step(total)
            return unless done == total || (done % step).zero?

            top_s = top.map { |rule, n| "#{rule}=#{n}" }.join(" ")
            Master::Trace::Dmesg.status(
              unit,
              "checkpoint #{done}/#{total} violations=#{viol_total} dirty_files=#{dirty}" \
              "#{eta_s && eta_s.positive? ? " eta=#{eta_s}s" : ""}" \
              " elapsed=#{elapsed.round}s" \
              "#{top_s.empty? ? "" : " top #{top_s}"}"
            )
            write_progress_snapshot(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
          end

          def log_scan_completion(unit:, done:, total:, viol_total:, dirty:, elapsed:)
            Master::Trace::Dmesg.kv(
              unit,
              complete: true, files: total, violations: viol_total,
              dirty_files: dirty, elapsed_s: elapsed.round
            )
          end

          def checkpoint_step(total)
            return 1 if total <= 10
            return 5 if total <= 50
            return 10 if total <= 100

            [25, (total / 10.0).ceil].max
          end

          def finding_rule_id(finding)
            return finding.rule.to_s if finding.respond_to?(:rule)
            return finding[:rule].to_s if finding.respond_to?(:[]) && finding[:rule]

            nil
          end

          def write_progress_snapshot(unit:, done:, total:, viol_total:, dirty:, top:, elapsed:, eta_s:)
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
              Master::CLI::ScanLive.snapshot!(text, root: root, note: "streaming checkpoint", announce: false)
            end
          rescue StandardError => e
            Master::Ground::Swallow.log(e, context: "Scanner.write_progress_snapshot")
          end
        end
      end
    end
  end
end
