# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "set"
require "time"

module Master
  module Loop
    class FixLoop
      class PassRunner
        PASS_BUDGET_SECONDS = 8 * 60

        PassResult = Struct.new(:status, :message, :consecutive_clean, keyword_init: true)

        def initialize(bus:, committer:, loop_scanner:, llm_router:, rollback:, root:,
                       rules:, agent:, scanner:, learnings:, preamble:,
                       clean_runs_required:, plateau_window:)
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
            return 0
          end
          if (avg = system_load_avg) && avg > Ops::ProcessBudget.config.dig("load", "load_avg_1m", "crit").to_f
            @bus&.publish("fix_loop:llm_skipped", pass:, reason: "load_shed", load: avg)
            sleep 60
            return 0
          end
          pass_deadline = [Time.now + PASS_BUDGET_SECONDS, deadline].min
          llm_fixed = llm_pass(violations: found, files:, pass:, deadline: pass_deadline)
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

        def ground_truth_violations(files) = violations(files)

        def mtimes(files) = files.to_h { |p| [p, File.exist?(p) ? File.mtime(p).to_f : nil] }

        def quiescent?(files, before)
          mtimes(files) == before
        rescue StandardError
          false
        end

        def fast_pass(files)
          fixed = 0
          rb = files.select { |f| f.end_with?(".rb") }
          if rb.any?
            _, status = Open3.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", "-q", *rb, chdir: @root)
            fixed += status.success? ? rb.size : rubocop_each_file(rb)
          end
          rb.each do |path|
            next unless File.exist?(path)
            fixed += analyze_ruby_file(path)
          rescue StandardError => e
            @bus&.publish("fix_loop:fast_error", file: path, error: e.message)
          end
          fixed
        end

        def rubocop_each_file(files)
          files.count do |path|
            _, status = Open3.capture2e(Master::BUNDLE_BIN, "exec", "rubocop", "-A", "--no-color", "-q", path, chdir: @root)
            @bus&.publish("fix_loop:rubocop_file_failed", file: path) unless status.success?
            status.success?
          end
        end

        def analyze_ruby_file(path)
          src = File.read(path, encoding: "UTF-8")
          fixed = 0
          rel   = path.delete_prefix("#{@root}/")

          ast_result = Judge::Scan::AstFixer.fix(path, src)
          if ast_result&.changed
            src = File.read(path, encoding: "UTF-8")
            fixed += ast_result.transforms.size
            @bus&.publish("fix_loop:ast_fixed", file: rel, transforms: ast_result.transforms)
          end

          Ground::TypeChecker.check(path, src).each do |te|
            @bus&.publish("fix_loop:type_error", file: rel, rule: te.rule, message: te.message)
          end

          dl = Judge::Scan::DatalogEngine.from_ruby(path, src)
          dl.rule(:BARE_RESCUE_DATALOG, :bare_rescue) { |f| "bare rescue at line #{f.args[1]} — use rescue StandardError" }
          dl.evaluate.each do |finding|
            @bus&.publish("fix_loop:datalog_finding", file: rel, rule: finding.rule_id, message: finding.message)
          end

          fixed
        end

        def llm_pass(violations:, files:, pass:, deadline: nil)
          fixed = 0
          rule_violations = violations.group_by { |v| v[:rule].to_s }
          runnable = @rule_order.ordered(violation_counts: @violation_counts)
                                .select { |rule| rule_violations.key?(rule.id.to_s) }
          @rule_order.dependency_levels(runnable).each do |group|
            break if deadline && Time.now >= deadline
            break if circuit_open?
            results = run_rule_group(group:, files:, pass:, rule_violations:)
            results.each do |rule, result|
              @violation_counts[rule.id] += result[:fixed]
              fixed += result[:fixed]
              @bus&.publish("fix_loop:rule_result", pass:, rule: rule.id, **result)
            end
          end
          if deadline && Time.now >= deadline
            @bus&.publish("fix_loop:pass_timeout", pass:)
          elsif circuit_open?
            @bus&.publish("fix_loop:llm_skipped", pass:, reason: "circuit_open", open: open_breakers)
          end
          fixed
        end

        def run_rule_group(group:, files:, pass:, rule_violations:)
          return group.map { |rule| [rule, run_rule_once(rule, files, pass)] } unless disjoint_rule_files?(group, rule_violations)

          group.map { |rule| Thread.new { [rule, run_rule_once(rule, files, pass)] } }.map(&:value)
        end

        def run_rule_once(rule, files, pass)
          rl = RuleLoop.new(rule:, agent: @agent, scanner: @scanner, root: @root, bus: @bus, learnings: @learnings)
          rl.injected_preamble = @preamble
          @bus&.publish("fix_loop:tier2_quality_route", pass:, rule: rule.id) if @rule_order.tier2?(rule.id)
          rl.run_once(files)
        end

        def disjoint_rule_files?(rules, rule_violations)
          seen = Set.new
          rules.all? do |rule|
            files = Array(rule_violations[rule.id.to_s]).map { |v| v[:file].to_s }.uniq
            overlap = files.any? { |f| seen.include?(f) }
            files.each { |f| seen << f }
            !overlap
          end
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

        def stagnant?(history, seen_snapshots, recurring_violations, found, pass)
          snap = violation_snapshot(found)
          if seen_snapshots.include?(snap)
            @bus&.publish("fix_loop:oscillation", pass:, violations: found.size)
            trigger_rollback("fix loop oscillation")
            return true
          end
          seen_snapshots << snap

          recurring = recurring_violation(found, recurring_violations)
          if recurring
            @bus&.publish("fix_loop:cycle_detected", pass:, threshold: @plateau_window, violation: recurring)
            trigger_rollback("fix loop cycle detected")
            return true
          end

          history << found.size
          window = @plateau_window
          if history.size >= window && history.last(window).uniq.size == 1
            @bus&.publish("fix_loop:plateau", pass:, violations: found.size)
            return true
          end
          false
        end

        def recurring_violation(found, recurring_violations)
          current = found.to_h { |v| [violation_key(v), v] }
          (recurring_violations.keys - current.keys).each { |key| recurring_violations.delete(key) }
          current.each do |key, violation|
            recurring_violations[key] += 1
            return violation if recurring_violations[key] >= @plateau_window
          end
          nil
        end

        def violation_snapshot(found)
          Digest::SHA256.hexdigest(found.map { |v| violation_key(v) }.sort.join("|"))
        end

        def violation_key(v) = "#{v[:rule]}:#{v[:file]}:#{v[:line]}"

        def trigger_rollback(message)
          return unless @rollback
          @rollback.call(Master::Result.err(message, category: :policy))
        rescue StandardError => e
          @bus&.publish("fix_loop:rollback_error", error: e.message)
        end

        def circuit_open? = @llm_router.circuit_open?
        def open_breakers = @llm_router.open_breakers

        def system_load_avg
          out, _, st = Open3.capture3("/sbin/sysctl", "-n", "vm.loadavg")
          return unless st.success?
          out.to_s[/\d+(?:\.\d+)?/]&.to_f
        rescue StandardError
          nil
        end
      end
    end
  end
end
