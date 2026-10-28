# frozen_string_literal: true

require_relative "../../review/council/critique"
require_relative "../../fix/execution_trace"
require_relative "../../fix/check_focus"
require_relative "../../fix/work_lane"
require_relative "../../fix/lane_preflight"
require_relative "../pipeline/residual"
require_relative "../../operator/check_chain"
require_relative "../../boot/paths"

module Master
  module CLI
    module CommandRegistry
      module_function

      SNAPSHOT_FILE_BYTES = 8_000
      SNAPSHOT_DIR_FILE_BYTES = 1_200
      SNAPSHOT_DIR_TOTAL_BYTES = 32_000
      SNAPSHOT_DIR_FILE_LIMIT = 40
      SNAPSHOT_EXTENSIONS = %w[.rb .erb .yml].freeze
      SNAPSHOT_SKIP_SEGMENTS = %w[
        .git .bundle node_modules vendor tmp log coverage storage cache dist build knowledge public var
      ].freeze

      # /review is a read-only compatibility adapter over the canonical /fix
      # pipeline. It cannot turn writes back on, even if a stale caller passes
      # --apply.
      def dispatch_review(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, swarm: nil, **_legacy)
        raw = arg_for(ctx).to_s.strip
        _apply, critique, aesthetic, only, target = parse_pass_flags(raw)
        selected = only || "fix,critique,map"
        selected = selected.split(",").reject { |stage| stage.strip == "fix" }.join(",")
        selected = "critique,map" if selected.empty?
        selected = "critique,map" if critique == false && only.nil?
        with_dmesg_verbosity(raw) do
          run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                   target:, apply: false, critique: critique != false, aesthetic:, only: selected)
        end
      end

      # /fix — the convergence lifecycle, and the only operation that writes.
      # It observes, critiques, generates and picks between repairs, applies
      # one, validates it and observes again, until the tree converges, stops
      # improving, or hands back a state only a person can settle. `--dry-run`
      # stops after the reading and says what it would take on.
      # /critique is a read-only compatibility adapter. The canonical lifecycle
      # is /fix; this method preserves the explicit council-only entry point.
      def dispatch_critique(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, swarm: nil, **_legacy)
        raw = arg_for(ctx).to_s.strip
        _apply, _critique, aesthetic, _only, target = parse_pass_flags(raw)
        with_dmesg_verbosity(raw) do
          run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                   target:, apply: false, critique: true, aesthetic:, only: "critique")
        end
      end

      MAX_FIX_CHECK_ROUNDS = Integer(ENV.fetch("MASTER_FIX_CHECK_ROUNDS", "5"))

      # Command-line overrides are temporary: a setting on one turn must
      # not change how the next command repairs the repository.
      def dispatch_fix(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, swarm: nil, **_legacy)
        raw = arg_for(ctx).to_s.strip
        apply, critique, aesthetic, only, target = parse_pass_flags(raw)
        overrides = execution_overrides(raw)
        previous_mode = Master::Fix::AutofixGuard.explicit_mode_override
        previous_max_files = Master::Fix::RunLedger.max_files_override
        previous_blockers = Master::Fix::CheckFocus.blockers?
        previous_plan = Master::Fix::CheckFocus.plan?
        previous_until = Master::Fix::CheckFocus.until_checks?
        previous_lane = Master::Fix::WorkLane.current

        cancellation = ctx.cancellation if ctx.respond_to?(:cancellation)
        cancellation.activate! if cancellation&.respond_to?(:activate!)

        begin
          Master::Fix::AutofixGuard.mode = overrides[:autofix_mode] if overrides[:autofix_mode]
          Master::Fix::RunLedger.max_files = overrides[:max_files] if overrides[:max_files]
          Master::Fix::CheckFocus.blockers! if overrides[:blockers]
          Master::Fix::CheckFocus.plan! if overrides[:plan]
          Master::Fix::CheckFocus.until_checks! if overrides[:until_checks]
          Master::Fix::WorkLane.set!(overrides.fetch(:lane))
          dispatch_fix_parsed(
            scanner:, fix_loop:, deliberation:, root:, bus:, swarm:, raw:,
            apply:, critique:, aesthetic:, only:, target:, cancellation:
          )
        ensure
          Master::Fix::AutofixGuard.restore_mode_override(previous_mode)
          Master::Fix::RunLedger.restore_max_files_override(previous_max_files)
          Master::Fix::CheckFocus.restore_blockers(previous_blockers)
          Master::Fix::CheckFocus.restore_plan(previous_plan)
          Master::Fix::CheckFocus.restore_until_checks(previous_until)
          Master::Fix::WorkLane.restore(previous_lane)
        end
      end

      # The last run on this target named the files its red checks pointed at; they come first again.
      def resume_from_residual(target)
        left = Master::CLI::Pipeline::Residual.read(File.basename(target.to_s))
        return unless left

        Master::Fix::CheckFocus.note(left["named"])
        Master::Trace::Dmesg.status("fix0", "resuming: last run #{left["scorecard"].to_s[0, 120]}")
      end

      # A trace refuses bytes that changed while it read them. In a checkout other writers share,
      # one of their saves landing mid-read refused the whole run; a trace that failed only on such
      # drift is read again, up to TRACE_ATTEMPTS times, and refuses only if the drift persists.
      TRACE_ATTEMPTS = 3
      TRACE_DRIFT = /changed during preflight|content differs during|file inventory changed during preflight/
      TRACE_PAUSE = Float(ENV.fetch("MASTER_FIX_TRACE_PAUSE", "2"))

      def steady_trace(scope:, dependencies:, cancellation: nil)
        (1..TRACE_ATTEMPTS).each do |attempt|
          trace = execution_trace(scope:, dependencies:)
          return trace if cancellation&.cancelled?
          return trace if trace.clean? || attempt == TRACE_ATTEMPTS || !trace.failures.all?(TRACE_DRIFT)

          Master::Trace::Dmesg.status("trace0", "#{trace.failures.size} file(s) changed while read; " \
                                                "reading again, attempt #{attempt + 1} of #{TRACE_ATTEMPTS}")
          sleep TRACE_PAUSE
        end
      end

      def execution_trace(scope:, dependencies:)
        Master::Fix::ExecutionTrace.new(root: Master.repo_root, scope:, dependencies:).run
      rescue SyntaxError, StandardError => e
        Master::Fix::ExecutionTrace::Result.new(
          ok: false, files: 0, bytes: 0, ruby_files: 0, phases: {},
          failures: ["execution trace uncaught: #{e.class}: #{e.message}"]
        )
      end

      # The first step of every /fix: lay out the tree and let the model say what it would
      # reshape, before any Law scans. Inconclusive is reported and the run goes on.
      def first_read(deliberation:, bus:, targets:, persist: true, cancellation: nil)
        # An absent/inconclusive current read must not fall back to hints from an older run.
        results = Array(targets).to_h { |target| [target.to_s, []] }
        return results if ENV["MASTER_FIX_TREE"] == "0"
        unless deliberation
          Master::Trace::Dmesg.status("tree0", "no model lane, first read skipped")
          return results
        end

        reasoning = Master::Fix::TreeReasoning.new(agent: deliberation.agent, root: Master.repo_root, bus:)
        targets.each do |tree_target|
          return results if cancellation&.cancelled?

          result = reasoning.call(target: tree_target, persist:)
          Master::Trace::Dmesg.status("tree0", result.summary) unless result.answered?
          results[tree_target.to_s] = result.proposals.map(&:to_h) if result.answered?
        end
        results
      end

      # The second read, after the trace: the whole target reviewed with fresh eyes against the Laws.
      # Inconclusive is reported and the run goes on.
      def structural_review(deliberation:, bus:, targets:, persist: true, first_read_results: {}, cancellation: nil)
        return if ENV["MASTER_FIX_STRUCTURAL_REVIEW"] == "0"
        return Master::Trace::Dmesg.status("look0", "no model lane, structural review skipped") unless deliberation

        review = Master::Fix::StructuralReview.new(agent: deliberation.agent, root: Master.repo_root, bus:)
        targets.each do |review_target|
          return if cancellation&.cancelled?

          result = review.call(
            target: review_target,
            persist:,
            first_read_proposals: first_read_results.fetch(review_target.to_s, nil),
          )
          Master::Trace::Dmesg.status("look0", result.summary) unless result.answered?
        end
      end

      def dispatch_fix_parsed(scanner:, fix_loop:, deliberation:, root:, bus:, swarm:, raw:,
                              apply:, critique:, aesthetic:, only:, target:, cancellation: nil)
        Master::Fix::RunBudget.with_shared_run(
          root: Master::ROOT,
          max_passes: Master::Fix::FixLoop::ABSOLUTE_MAX_PASSES,
          bus:,
          target:,
        ) do
          next cancelled_fix_result(cancellation) if cancellation&.cancelled?

          writes_requested = writes_requested?(apply:, only:)
          display_target = display_fix_target(target)
          mode = writes_requested ? "write" : "read-only"
          boundary = writes_requested ? "current-checkout" : "no-write-or-publish"
          with_dmesg_verbosity(raw, default: "trace") do
            Master::Trace::Dmesg.status("fix0", "mode=#{mode} target=#{display_target} boundary=#{boundary}")
          end
          targets = fix_targets(target, root:)
          ::Operator::CheckChain.clear_verified_fix_snapshots! if writes_requested
          Master::Trace::Dmesg.status("fix0", "target queue: #{targets.join(", ")}") if targets.size > 1
          lane_refusal = Master::Fix::WorkLane.refusal(target)
          next Master::Result.err("fix: #{lane_refusal}", category: :validation) if lane_refusal
          Master::Trace::Dmesg.status("fix0", Master::Fix::WorkLane.summary)
          refusal = Master::Fix::LanePreflight.check(agent: deliberation.agent) if deliberation
          next cancelled_fix_result(cancellation) if cancellation&.cancelled?
          next refusal if refusal

          trace_scope = execution_trace_scopes(target)

          rendered = Master::Trace::Dmesg.with_log_voice do
            with_dmesg_verbosity(raw, default: "trace") do
              next cancelled_fix_result(cancellation) if cancellation&.cancelled?
              first_read_results = first_read(
                deliberation:, bus:, targets:, persist: writes_requested, cancellation:,
              )
              next cancelled_fix_result(cancellation) if cancellation&.cancelled?

              unless ENV["MASTER_FIX_DEEP_TRACE"] == "0"
                trace = steady_trace(
                  scope: trace_scope, dependencies: { scanner:, fix_loop:, deliberation:, bus: }, cancellation:,
                )
                next cancelled_fix_result(cancellation) if cancellation&.cancelled?
                Master::Trace::Dmesg.status("trace0", trace.summary)
                unless trace.clean?
                  details = trace.failures.first(12).join(" | ")
                  message = "fix: execution trace failed — #{details}"
                  Master::Trace::Dmesg.status("trace0", message)
                  next Master::Result.err(message, category: :validation)
                end
              end

              structural_review(
                deliberation:, bus:, targets:, persist: writes_requested, first_read_results:, cancellation:,
              )
              next cancelled_fix_result(cancellation) if cancellation&.cancelled?

              writes_requested = writes_requested?(apply:, only:)
              effective_critique = critique.nil? ? writes_requested && council_default : critique

              results = targets.map do |fix_target|
                next cancelled_fix_result(cancellation) if cancellation&.cancelled?

                run_fix_target(
                  scanner:, fix_loop:, root:, deliberation:, bus:, swarm:,
                  target: fix_target, writes_requested:, effective_critique:, critique:, aesthetic:, only:,
                  cancellation:
                )
              end
              failure = results.find { |result| result.is_a?(Master::Result::Err) }
              next failure if failure

              # One push for the whole run, after every tree has verified.
              # A verified local repair is not a delivered repair: do not save the
              # candidate baseline as the published state when its final push fails.
              if writes_requested
                next cancelled_fix_result(cancellation) if cancellation&.cancelled?

                begin
                  fix_loop.publish_pending!
                rescue StandardError => e
                  message = "final publish failed after verification (#{e.class})"
                  Master::Trace::Dmesg.status("deliver0", "DELIVERY_FAILED: #{message}")
                  next Master::Result.err("DELIVERY_FAILED: #{message}", category: :delivery_failed)
                end
                ::Operator::CheckChain.persist_verified_baselines!(targets)
              end
              results.join("\n")
            end
          end
          return rendered unless Master::Fix::CodeWatch.requested?

          # A run that stopped for newer code continues on it, in this process.
          puts rendered
          Master::Fix::CodeWatch.reexec!(root, "/fix #{raw}")
          rendered
        end
      end

      def run_fix_target(scanner:, fix_loop:, root:, deliberation:, bus:, swarm:, target:,
                         writes_requested:, effective_critique:, critique:, aesthetic:, only:, cancellation: nil)
        check_label = ::Operator::CheckChain.baseline_scope_key(target)
        # What already fails, taken before any repair, so delivery can be judged on
        # what the run added instead of on debt it did not create. This scan-only
        # check is a baseline phase, not the requested repair's execution mode.
        baseline = nil
        return cancelled_fix_result(cancellation) if cancellation&.cancelled?
        Master::Fix::CheckFocus.reset!
        resume_from_residual(target)
        if writes_requested || Master::Fix::CheckFocus.plan?
          Master::Trace::Dmesg.status("check0", "scope #{check_label}: capturing read-only pre-repair baseline")
          baseline = begin
            ::Operator::CheckChain.baseline(target:)
          rescue ::Operator::CheckChain::BaselineMutation => e
            Master::Trace::Dmesg.status("check0", "scope #{check_label}: pre-repair baseline blocked; no repair started")
            return Master::Result.err("pre-repair proof blocked: #{e.message}", category: :validation)
          rescue ::Operator::CheckChain::InvalidVerificationScope => e
            Master::Trace::Dmesg.status("check0", "scope #{check_label}: invalid verification scope; no repair started")
            return Master::Result.err("verification scope invalid: #{e.message}", category: :validation)
          end
          # The lexical stage lists every finding; the other stages name what keeps a check red.
          Master::Fix::CheckFocus.note(baseline.except("lexical").values.flatten)
          next_step = writes_requested ? "starting write-enabled /fix pass" : "planning, nothing is written"
          Master::Trace::Dmesg.status("check0", "scope #{check_label}: baseline ready; #{next_step}")
        end
        return cancelled_fix_result(cancellation) if cancellation&.cancelled?

        value = run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                         target:, apply: writes_requested, critique: effective_critique,
                         aesthetic:, only:, cancellation:)
        return cancelled_fix_result(cancellation) if cancellation&.cancelled?
        return value unless writes_requested
        return incomplete_fix_pipeline(value) if incomplete_fix_pipeline?(value)

        check_rounds = 0
        check_status = 0
        check_changed = []
        loop do
          return cancelled_fix_result(cancellation) if cancellation&.cancelled?

          check_status, check_changed = ::Operator::CheckChain.verify_fix(target:, baseline:)
          check_rounds += 1
          break if check_status == 0 && check_changed.empty?
          break if check_changed.empty? || check_rounds >= MAX_FIX_CHECK_ROUNDS

          Master::Trace::Dmesg.status(
            "check0", "verification changed #{check_changed.size} file(s), re-entering /fix"
          )
          value = run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                           target:, apply: true, critique: critique.nil? ? council_default : critique,
                           aesthetic:, only: "fix", cancellation:)
          return cancelled_fix_result(cancellation) if cancellation&.cancelled?
          return incomplete_fix_pipeline(value) if incomplete_fix_pipeline?(value)
        end

        if check_status != 0
          message = "check verification did not pass (status #{check_status})"
          Master::Trace::Dmesg.status("check0", "scope #{check_label}: #{message}")
          return Master::Result.err(message, category: :validation)
        end
        if check_rounds >= MAX_FIX_CHECK_ROUNDS && check_changed.any?
          message = "check verification reached #{MAX_FIX_CHECK_ROUNDS} rounds without a stable tree"
          Master::Trace::Dmesg.status("check0", "#{target}: #{message}")
          return Master::Result.err(message, category: :validation)
        end

        Master::Trace::Dmesg.status("check0", "scope #{check_label}: delivery verified")
        value
      end

      # The report footer, at the start of a line. A patch in the same report can quote these words, and
      # a quoted one is not the pipeline failing.
      FOOTER_INCOMPLETE = /\Areview\d+:\s*incomplete\b/i
      FOOTER_OPEN_FINDINGS = /\Areview\d+:\s*complete with open findings\b/i
      FOOTER_CAUSE = /\Areview\d+:\s*cause,/i

      # run_pass returns a rendered report for compatibility. Do not allow its
      # textual failure state to fall through into check success and publication.
      def incomplete_fix_pipeline?(value)
        value.to_s.lines.any? { |line| line.match?(FOOTER_INCOMPLETE) || line.match?(FOOTER_OPEN_FINDINGS) }
      end

      def incomplete_fix_pipeline(value)
        lines = value.to_s.lines
        detail = lines.find { |line| line.match?(FOOTER_INCOMPLETE) || line.match?(FOOTER_OPEN_FINDINGS) }.to_s.strip
        cause = footer_cause(lines)
        head = detail.empty? ? "" : ": #{detail}"
        tail = cause.empty? ? "" : "; cause #{cause}"
        message = "fix pipeline incomplete#{head}#{tail}"
        Master::Trace::Dmesg.status("fix0", message[0, 200])
        Master::Result.err(message, category: :validation)
      end

      def cancelled_fix_result(cancellation)
        reason = cancellation.respond_to?(:reason) ? cancellation.reason : nil
        detail = reason.to_s.strip
        message = detail.empty? ? "CANCELLED: /fix stopped at a safe stage boundary" :
          "CANCELLED: /fix stopped at a safe stage boundary (#{detail})"
        Master::Result.err(message, category: :cancelled)
      end

      # The first `review0: cause, <stage>: <reason>` footer line, as `<stage>: <reason>`.
      def footer_cause(lines)
        found = lines.find { |line| line.match?(FOOTER_CAUSE) }.to_s.strip
        found.sub(/\Areview\d+:\s*cause,\s*/i, "")
      end

      # Whether /fix convenes the council when no flag says: only when MASTER_FIX_COUNCIL=1.
      def council_default = Master::Review::LLMDispatcher::PassClock.council_enabled?

      def execution_trace_scopes(target)
        raw = target.to_s.strip
        return if raw.empty?

        trees = MasterPaths::TREES.dup
        tokens = raw.split(/\s+/)
        return tokens if tokens.size > 1 && tokens.all? { |token| trees.include?(token) }

        tokens.map { |token| token.sub(%r{\A\.\./(?=[A-Z]+(?:/|\z))}, "") }
      end

      def fix_targets(target, root:)
        tokens = target.to_s.split(/\s+/)
        trees = MasterPaths::TREES.dup
        return [target] unless tokens.size > 1 && tokens.all? { |token| trees.include?(token) }

        # The session root is the directory bin/master started in; a start inside any tree
        # (RAILS/brgen, MASTER/lib) still names the four trees of this checkout.
        repo_root = File.expand_path(root)
        repo_root = Master::REPO_ROOT if repo_root.start_with?("#{Master::REPO_ROOT}/")
        tokens.uniq.map { |tree| File.join(repo_root, tree) }
      end

      def run_pass(deps, **call_args)
        Master::CLI::Pipeline::Pass.new(**deps).call(**call_args).render
      end

      # /fix may select a read-only stage with --only. Apply permission never
      # turns critique/map into a write path; only the fix stage can mutate.
      def fix_stage_selected?(only)
        return true if only.nil?

        Array(only.to_s.split(",")).map(&:strip).any? { |stage| %w[fix converge].include?(stage.downcase) }
      end

      # The canonical /fix command writes unless a caller explicitly asks for
      # read-only work. Review/critique adapters pass apply:false themselves.
      def writes_requested?(apply:, only:)
        apply != false && fix_stage_selected?(only)
      end

      # `--only critique` and `--only map` select read-only review stages.
      # /fix is not a review-stage alias: TurnRouter sends it to dispatch_fix,
      # which owns the complete observe/repair/re-observe lifecycle. There is
      # no /scan stage; observation is the first step of /fix.
      # Every spelling a flag answers to, and the flag it sets. A table rather
      # than a `case`, because the spellings are data: `--no-autofix` is
      # bin/check --ladder's, and while it was missing it fell through to the path,
      # resolved nowhere, and the scan quietly ran over MASTER instead.
      DMESG_FLAGS = {
        "--quiet" => "quiet", "quiet" => "quiet",
        "--normal" => "normal", "normal" => "normal",
        "--verbose" => "verbose", "verbose" => "verbose",
        "--trace" => "trace", "trace" => "trace"
      }.freeze

      PASS_FLAGS = {
        "--dry-run" => [:apply, false], "preview" => [:apply, false], "dry" => [:apply, false],
        "--plan" => [:apply, false],
        "--no-autofix" => [:apply, false], "no-autofix" => [:apply, false],
        "--apply" => [:apply, true], "apply" => [:apply, true], "fix" => [:apply, true],
        "--no-critique" => [:critique, false], "no-critique" => [:critique, false],
        "--critique" => [:critique, true], "critique" => [:critique, true],
        "--no-aesthetic" => [:aesthetic, false], "no-aesthetic" => [:aesthetic, false]
      }.freeze

      # A bare `--only` captures nothing and leaves the stage unset, which is what
      # the split spelling did before it was joined.
      ONLY_FLAG = /\A--only(?:=(.+))?\z/i

      # off, dry or on: what the deterministic autofix stage may do (Fix::AutofixGuard).
      AUTOFIX_FLAG = /\A--autofix=(off|dry|on)\z/i

      # How many files the model phase takes, easiest first (Fix::RunLedger.max_files).
      MAX_FILES_FLAG = /\A--max-files=(\d+)\z/i

      # Repair only the files a red check names, without semantic reads (Fix::CheckFocus).
      BLOCKERS_FLAG = /\A--blockers\z/i

      # code, visual or all: which half of /fix runs (Fix::WorkLane).
      LANE_FLAG = /\A--lane=(code|visual|all)\z/i

      # Flags read per dispatch (execution_overrides), never part of the target.
      DISPATCH_FLAG = Regexp.union(AUTOFIX_FLAG, MAX_FILES_FLAG, BLOCKERS_FLAG, LANE_FLAG, /\A--until-checks\z/i)

      # Status messages are one-line operator evidence. Do not let a path label
      # inject terminal controls or forged log lines into the dmesg stream.
      def display_fix_target(target)
        display = target.to_s.gsub(/[\x00-\x1f\x7f]/, " ").gsub(/\s+/, " ").strip
        display = "MASTER" if display.empty? || display == "." || display.casecmp?("master")
        display = "all trees" if %w[all everything].any? { |name| display.casecmp?(name) }
        display[0, 80]
      end

      def execution_overrides(raw)
        tokens = raw.to_s.split(/\s+/).map(&:downcase)
        lane = tokens.filter_map { |token| token[LANE_FLAG, 1] }.last || Master::Fix::WorkLane::DEFAULT.to_s
        overrides = { autofix_mode: nil, max_files: nil, blockers: false, lane:, plan: tokens.include?("--plan"),
                      until_checks: tokens.include?("--until-checks") }
        raw.to_s.split(/\s+/).each do |token|
          if (match = AUTOFIX_FLAG.match(token))
            overrides[:autofix_mode] = match[1]
          elsif (match = MAX_FILES_FLAG.match(token))
            overrides[:max_files] = match[1]
          elsif BLOCKERS_FLAG.match?(token)
            overrides[:blockers] = true
          end
        end
        overrides
      end

      def parse_pass_flags(raw)
        flags = { apply: nil, critique: nil, aesthetic: true, only: nil }
        path_bits = []
        joined_only(raw.split(/\s+/)).each do |token|
          if (flag = PASS_FLAGS[token.downcase])
            flags[flag.first] = flag.last
          elsif DMESG_FLAGS.key?(token.downcase)
            next
          elsif token.match?(DISPATCH_FLAG)
            # Parsed below as per-dispatch options; parsing must not mutate the
            # next command's behavior in a long-lived interactive session.
            next
          elsif token =~ ONLY_FLAG
            flags[:only] = Regexp.last_match(1)
          else
            path_bits << token
          end
        end
        flags.values_at(:apply, :critique, :aesthetic, :only) + [path_bits.join(" ")]
      end

      # `--only scan` and `--only=scan` are one flag with its value in two places.
      # Joining the split form here keeps that out of the loop, which otherwise
      # needs a carried flag and a branch that reads as a third kind of token.
      def joined_only(tokens)
        tokens.each_with_object([]) do |token, out|
          out.last&.casecmp?("--only") ? out[-1] = "--only=#{token}" : out << token
        end
      end

      def with_dmesg_verbosity(raw, default: nil)
        level = raw.to_s.split(/\s+/).filter_map { |token| DMESG_FLAGS[token.downcase] }.last
        level ||= default
        return yield unless level

        Master::Trace::Dmesg.with_verbosity(level) { yield }
      end

      def snapshot_artifact(abs_path)
        return "not found: #{abs_path}" unless File.exist?(abs_path)
        return snapshot_truncate(File.read(abs_path), SNAPSHOT_FILE_BYTES) if File.file?(abs_path)

        files = snapshot_files(abs_path)
        files.map do |f|
          "--- #{f.sub(abs_path + "/", "")} ---\n#{snapshot_truncate(File.read(f), SNAPSHOT_DIR_FILE_BYTES)}"
        end.join("\n\n")[0, SNAPSHOT_DIR_TOTAL_BYTES]
      end

      # Byte-truncate via .b (so a byte limit can't be exceeded by a
      # multi-byte char) but re-tag as UTF-8 and scrub afterward -- callers
      # concatenate this into UTF-8 prompt text, and a truncation boundary
      # landing mid-character otherwise raises Encoding::CompatibilityError
      # the moment it's joined with anything not itself forced to BINARY
      # (confirmed live: every /critique persona failing with exactly that
      # error, tracing back to this truncation never restoring the tag).
      def snapshot_truncate(text, byte_limit)
        text.b[0, byte_limit].force_encoding("UTF-8").scrub
      end

      def snapshot_files(abs_path)
        pending = [abs_path]
        files = []
        until pending.empty? || files.size >= SNAPSHOT_DIR_FILE_LIMIT
          scan_snapshot_dir(pending.shift, pending, files)
        end
        files
      end

      def scan_snapshot_dir(current, pending, files)
        Dir.children(current).sort.each do |entry|
          path = File.join(current, entry)
          next if snapshot_skip_path?(path)

          add_snapshot_entry(path, pending, files)
          break if files.size >= SNAPSHOT_DIR_FILE_LIMIT
        end
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "CommandRegistry.scan_snapshot_dir")
        nil
      end

      def add_snapshot_entry(path, pending, files)
        return pending << path if File.directory?(path)

        files << path if snapshot_file?(path)
      end

      def snapshot_skip_path?(path)
        segments = path.split(File::SEPARATOR)
        SNAPSHOT_SKIP_SEGMENTS.any? { |segment| segments.include?(segment) }
      end

      def snapshot_file?(path)
        File.file?(path) && SNAPSHOT_EXTENSIONS.include?(File.extname(path))
      end
    end
  end
end
