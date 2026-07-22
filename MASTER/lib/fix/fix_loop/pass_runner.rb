# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "set"
require "time"
require_relative "pass_runner/fast_stage"
require_relative "pass_runner/llm_stage"
require_relative "pass_runner/stagnation_detection"

module Master
  module Fix
    class FixLoop
      class PassRunner
        PASS_BUDGET_SECONDS = 8 * 60

        PassResult = Struct.new(:status, :message, :consecutive_clean, keyword_init: true)

        include FastStage
        include LlmStage
        include StagnationDetection

        def initialize(bus:, committer:, loop_scanner:, llm_router:, rollback:, root:,
                       rules:, agent:, scanner:, learnings:, preamble:,
                       clean_runs_required:, plateau_window:, ground_truth: nil)
          @bus = bus
          @committer = committer
          @loop_scanner = loop_scanner
          @llm_router = llm_router
          @rollback = rollback
          @root = root
          @agent = agent
          @scanner = scanner
          @learnings = learnings
          @preamble = preamble
          @clean_runs_required = clean_runs_required
          @plateau_window = plateau_window
          @rule_order = RuleOrder.new(rules:, learnings:, bus:, root:)
          @violation_counts = Hash.new(0)
          @rule_recurrence = Hash.new(0)
          @ground_truth = ground_truth
        end

        def violations(files) = @loop_scanner.violations(files)

        def run_pass(files:, target:, pass:, deadline:, history:, seen_snapshots:,
                     recurring_violations:, consecutive_clean:)
          pass_mtimes = mtimes(files)
          @bus&.publish("fix_loop:pass_start", pass:, target:, file_count: files.size)

          run_fast_stage(files, pass)
          found = run_scan_stage(files, target)
          return handle_clean_pass(files, pass_mtimes, pass, consecutive_clean) if found.empty?
          return PassResult.new(status: :plateau, consecutive_clean: 0) if stagnant?(history, seen_snapshots, recurring_violations, found, pass)

          run_llm_stage(found, files, pass, deadline)
          PassResult.new(status: :continue, consecutive_clean: 0)
        end

        private

        def run_fast_stage(files, pass)
          fixed = fast_pass(files)
          @committer.commit_if_dirty("fix_loop: fast-fix [pass #{pass}]") if fixed > 0
          fixed
        end

        def run_scan_stage(files, target)
          violations(files).tap { |v| emit_topology(v, target) }
        end

        def run_llm_stage(found, files, pass, deadline)
          if circuit_open?
            @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
            Master::Trace::Dmesg.status("fix0", "llm_skipped pass=#{pass} reason=circuit_open open=#{open_breakers.join(" ")}")
            return 0
          end
          if (avg = system_load_avg) && avg > Ops::ProcessBudget.config.dig("load", "load_avg_1m", "crit").to_f
            @bus&.publish("fix_loop:llm_skipped", pass:, reason: "load_shed", load: avg)
            Master::Trace::Dmesg.status("fix0", "llm_skipped pass=#{pass} reason=load_shed load=#{avg}")
            sleep 60
            return 0
          end
          pass_deadline = [Time.now + PASS_BUDGET_SECONDS, deadline].min
          llm_fixed = llm_pass(violations: found, files:, pass:, deadline: pass_deadline)
          Master::Trace::Dmesg.status("fix0", "llm_pass pass=#{pass} violations=#{found.size} fixed=#{llm_fixed}")
          @committer.commit_if_dirty("fix_loop: llm-fix [pass #{pass}]") if llm_fixed > 0
          track_recurrence(found)
          llm_fixed
        end

        def handle_clean_pass(files, pass_mtimes, pass, consecutive_clean)
          ground_truth = ground_truth_violations(files)
          unless ground_truth.empty?
            @bus&.publish("fix_loop:ground_truth_failed", pass:, violations: ground_truth.size)
            return PassResult.new(status: :continue, consecutive_clean: 0)
          end
          @bus&.publish("fix_loop:ground_truth_ok", pass:)
          unless quiescent?(files, pass_mtimes)
            @bus&.publish("fix_loop:quiesce_wait", pass:)
            return PassResult.new(status: :continue, consecutive_clean: 0)
          end
          clean_count = consecutive_clean + 1
          @bus&.publish("fix_loop:clean", pass:, consecutive_clean: clean_count)
          status = clean_count >= @clean_runs_required ? :clean : :continue
          PassResult.new(status: status, message: "clean after #{pass} pass(es)", consecutive_clean: clean_count)
        end

        def ground_truth_violations(files)
          return [] unless @ground_truth

          files.filter_map do |path|
            next unless File.exist?(path)

            result = @ground_truth.assert_fresh!(path, reason: "claim_task_complete")
            next if result.ok?

            { rule: "GROUND_TRUTH", file: path.delete_prefix("#{@root}/"), line: 0, message: result.message }
          end
        end

        def mtimes(files) = files.to_h { |p| [p, File.exist?(p) ? File.mtime(p).to_f : nil] }

        def quiescent?(files, before)
          mtimes(files) == before
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "PassRunner.quiescent?")
          false
        end

        def emit_topology(found, target)
          by_mod = found.group_by { |v| v[:file].to_s.split("/").first(3).join("/") }.transform_values(&:size)
          @bus&.publish("codebase:topology", {
            timestamp: Time.now.utc.iso8601,
            target: target.delete_prefix("#{@root}/"),
            total_violations: found.size,
            any_dirty: found.any?,
            modules: by_mod.map { |path, count| { path:, violations: count } }
          })
        end

        def track_recurrence(found)
          tally = found.group_by { |v| v[:rule].to_s }.transform_values(&:size)
          tally.each do |rule_id, _|
            @rule_recurrence[rule_id] += 1
            next unless @rule_recurrence[rule_id] >= 3
            @rule_recurrence.delete(rule_id)
            sample = found.select { |v| v[:rule].to_s == rule_id }.first(5)
            @bus&.publish("fix_loop:soul_proposal", rule: rule_id, sample:)
            append_improvement(rule_id, sample)
          end
          (@rule_recurrence.keys - tally.keys).each { |k| @rule_recurrence.delete(k) }
        end

        def append_improvement(rule_id, sample)
          files = sample.map { |v| v[:file] }.uniq.first(3).join(", ")
          @bus&.publish("loop:recurrence", rule: rule_id, files:, at: Time.now.utc.iso8601)
          line = "#{Time.now.utc.strftime("%Y-%m-%d %H:%M")} #{rule_id}: recurring in #{files}\n"
          %w[runtime/improvements.md runtime/rsi_improvements.md].each do |rel|
            path = File.join(@root, rel)
            FileUtils.mkdir_p(File.dirname(path))
            File.open(path, "a") { |f| f.write(line) }
          end
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "fix_loop.append_improvement", event_bus: @bus, rule_id:)
        end

        def circuit_open? = @llm_router.circuit_open?
        def open_breakers = @llm_router.open_breakers

        def system_load_avg
          out, _, st = Master::Io::Exec.capture3("/sbin/sysctl", "-n", "vm.loadavg")
          return unless st.success?
          out.to_s[/\d+(?:\.\d+)?/]&.to_f
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "PassRunner.system_load_avg")
          nil
        end
      end
    end
  end
end
