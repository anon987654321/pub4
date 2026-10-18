# frozen_string_literal: true

require_relative "../../review/council/critique"
require_relative "../../fix/execution_trace"
require_relative "../../operator/gate_chain"
require_relative "../../fix/worktree_session"
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

      MAX_FIX_GATE_ROUNDS = Integer(ENV.fetch("MASTER_FIX_GATE_ROUNDS", "5"))

      # Command-line overrides are temporary: a setting on one turn must
      # not change how the next command repairs the repository.
      def dispatch_fix(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, swarm: nil, **_legacy)
        raw = arg_for(ctx).to_s.strip
        apply, critique, aesthetic, only, target = parse_pass_flags(raw)
        overrides = execution_overrides(raw)
        previous_mode = Master::Fix::AutofixGuard.explicit_mode_override
        previous_max_files = Master::Fix::RunLedger.max_files_override

        begin
          Master::Fix::AutofixGuard.mode = overrides[:autofix_mode] if overrides[:autofix_mode]
          Master::Fix::RunLedger.max_files = overrides[:max_files] if overrides[:max_files]
          dispatch_fix_parsed(
            scanner:, fix_loop:, deliberation:, root:, bus:, swarm:, raw:,
            apply:, critique:, aesthetic:, only:, target:
          )
        ensure
          Master::Fix::AutofixGuard.restore_mode_override(previous_mode)
          Master::Fix::RunLedger.restore_max_files_override(previous_max_files)
        end
      end

      def dispatch_fix_parsed(scanner:, fix_loop:, deliberation:, root:, bus:, swarm:, raw:,
                              apply:, critique:, aesthetic:, only:, target:)
        targets = fix_targets(target, root:)
        writes_requested = writes_requested?(apply:, only:)
        display_target = target.to_s.strip
        display_target = "MASTER" if display_target.empty? || display_target == "." || display_target.casecmp?("master")
        display_target = "all trees" if %w[all everything].any? { |name| display_target.casecmp?(name) }
        display_target = display_target[0, 80]
        mode = writes_requested ? "write" : "read-only"
        boundary = if !writes_requested
                     "no-write-or-publish"
                   elsif ENV["MASTER_FIX_WORKTREE_CHILD"] == "1" || worktree_fix_requested?
                     "isolated-worktree"
                   else
                     "current-checkout"
                   end
        with_dmesg_verbosity(raw, default: "trace") do
          Master::Trace::Dmesg.status("fix0", "mode=#{mode} target=#{display_target} boundary=#{boundary}")
        end
        ::Operator::GateChain.clear_verified_fix_snapshots! if writes_requested
        if writes_requested && worktree_fix_requested?
          Master::Trace::Dmesg.status("fix0", "target queue: #{targets.join(", ")}") if targets.size > 1
          return Master::Trace::Dmesg.with_log_voice do
            with_dmesg_verbosity(raw, default: "trace") do
              dispatch_fix_in_worktree(raw:, root:, target:)
            end
          end
        end
        Master::Trace::Dmesg.status("fix0", "target queue: #{targets.join(", ")}") if targets.size > 1
        trace_scope = execution_trace_scopes(target)

        rendered = Master::Trace::Dmesg.with_log_voice do
          with_dmesg_verbosity(raw, default: "trace") do
          unless ENV["MASTER_FIX_DEEP_TRACE"] == "0"
            trace = begin
              Master::Fix::ExecutionTrace.new(
                root: Master.repo_root,
                scope: trace_scope,
                dependencies: { scanner:, fix_loop:, deliberation:, bus: },
              ).run
            rescue SyntaxError, StandardError => e
              Master::Fix::ExecutionTrace::Result.new(
                ok: false, files: 0, bytes: 0, ruby_files: 0, phases: {},
                failures: ["execution trace uncaught: #{e.class}: #{e.message}"]
              )
            end
            Master::Trace::Dmesg.status("trace0", trace.summary)
            unless trace.clean?
              details = trace.failures.first(12).join(" | ")
              message = "fix: execution trace failed — #{details}"
              Master::Trace::Dmesg.status("trace0", message)
              next Master::Result.err(message, category: :validation)
            end
          end

          writes_requested = writes_requested?(apply:, only:)
          effective_critique = critique.nil? ? writes_requested : critique

          results = targets.map do |fix_target|
            run_fix_target(
              scanner:, fix_loop:, root:, deliberation:, bus:, swarm:,
              target: fix_target, writes_requested:, effective_critique:, critique:, aesthetic:, only:
            )
          end
          failure = results.find { |result| result.is_a?(Master::Result::Err) }
          next failure if failure

          # One push for the whole run, after every tree has verified.
          # A verified local repair is not a delivered repair: do not save the
          # candidate baseline as the published state when its final push fails.
          if writes_requested
            begin
              fix_loop.publish_pending!
            rescue StandardError => e
              message = "final publish failed after verification (#{e.class})"
              Master::Trace::Dmesg.status("deliver0", "DELIVERY_FAILED: #{message}")
              next Master::Result.err("DELIVERY_FAILED: #{message}", category: :delivery_failed)
            end
            ::Operator::GateChain.persist_verified_baselines!(targets)
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

      def worktree_fix_requested?
        ENV.fetch("MASTER_FIX_WORKTREE", "1") != "0" && ENV["MASTER_FIX_WORKTREE_CHILD"] != "1"
      end

      def dispatch_fix_in_worktree(raw:, root:, target:)
        result = Master::Fix::WorktreeSession.new(root:).run(
          command: ["/fix", raw].reject(&:empty?).join(" "),
          foreign_paths: Master::Fix::WorktreeSession.foreign_paths(root:),
          proof_trees: worktree_proof_trees(target, root:),
          include_dirty: include_dirty_requested?(raw),
        )
        return result.summary if result.ok

        Master::Result.err(result.summary, category: :validation)
      end

      def include_dirty_requested?(raw)
        ENV["MASTER_FIX_INCLUDE_DIRTY"] == "1" || raw.to_s.split(/\s+/).any? { |token| token.casecmp?(INCLUDE_DIRTY_FLAG) }
      end

      def worktree_proof_trees(target, root:)
        text = target.to_s.strip
        trees = MasterPaths::TREES.dup
        # TargetResolver's omitted target, "." and "master" all mean MASTER.
        # Keep that scope through the isolated worker's final proof; all-tree
        # work must be requested explicitly.
        return ["MASTER"] if text.empty? || text == "." || text.casecmp?("master")
        return trees if %w[all everything].any? { |name| text.casecmp?(name) }

        tokens = text.split(/\s+/)
        return tokens.uniq if tokens.size > 1 && tokens.all? { |token| trees.include?(token) }

        repo_root = File.expand_path(root)
        repo_root = Master::REPO_ROOT if repo_root == Master::ROOT
        master_root = File.join(repo_root, "MASTER")
        [target].filter_map do |value|
          candidates = [
            File.expand_path(value.to_s, repo_root),
            File.expand_path(value.to_s, master_root),
          ].uniq
          candidates.filter_map do |path|
            trees.find do |tree|
              base = File.join(repo_root, tree)
              path == base || path.start_with?("#{base}#{File::SEPARATOR}")
            end
          end.first
        end.uniq
      end

      def run_fix_target(scanner:, fix_loop:, root:, deliberation:, bus:, swarm:, target:,
                         writes_requested:, effective_critique:, critique:, aesthetic:, only:)
        gate_label = ::Operator::GateChain.baseline_scope_key(target)
        # What already fails, taken before any repair, so delivery can be judged on
        # what the run added instead of on debt it did not create. This scan-only
        # gate is a baseline phase, not the requested repair's execution mode.
        baseline = nil
        if writes_requested
          Master::Trace::Dmesg.status("gate0", "scope #{gate_label}: capturing read-only pre-repair baseline")
          baseline = ::Operator::GateChain.baseline(target:)
          Master::Trace::Dmesg.status("gate0", "scope #{gate_label}: baseline ready; starting write-enabled /fix pass")
        end
        value = run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                         target:, apply: writes_requested, critique: effective_critique,
                         aesthetic:, only:)
        return value unless writes_requested
        return incomplete_fix_pipeline(value) if incomplete_fix_pipeline?(value)

        gate_rounds = 0
        gate_status = 0
        gate_changed = []
        loop do
          gate_status, gate_changed = ::Operator::GateChain.verify_fix(target:, baseline:)
          gate_rounds += 1
          break if gate_status == 0 && gate_changed.empty?
          break if gate_changed.empty? || gate_rounds >= MAX_FIX_GATE_ROUNDS

          Master::Trace::Dmesg.status(
            "gate0", "verification changed #{gate_changed.size} file(s), re-entering /fix"
          )
          value = run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                           target:, apply: true, critique: critique.nil? ? true : critique,
                           aesthetic:, only: "fix")
          return incomplete_fix_pipeline(value) if incomplete_fix_pipeline?(value)
        end

        if gate_status != 0
          message = "gate verification did not pass (status #{gate_status})"
          Master::Trace::Dmesg.status("gate0", "scope #{gate_label}: #{message}")
          return Master::Result.err(message, category: :validation)
        end
        if gate_rounds >= MAX_FIX_GATE_ROUNDS && gate_changed.any?
          message = "gate verification reached #{MAX_FIX_GATE_ROUNDS} rounds without a stable tree"
          Master::Trace::Dmesg.status("gate0", "#{target}: #{message}")
          return Master::Result.err(message, category: :validation)
        end

        Master::Trace::Dmesg.status("gate0", "scope #{gate_label}: delivery verified")
        value
      end

      # run_pass returns a rendered report for compatibility. Do not allow its
      # textual failure state to fall through into gate success and publication.
      def incomplete_fix_pipeline?(value)
        value.to_s.match?(/\breview\d+:\s*incomplete\b/i)
      end

      def incomplete_fix_pipeline(value)
        detail = value.to_s.lines.find { |line| line.match?(/\breview\d+:\s*incomplete\b/i) }.to_s.strip
        message = "fix pipeline incomplete#{detail.empty? ? "" : ": #{detail}"}"
        Master::Trace::Dmesg.status("fix0", message[0, 200])
        Master::Result.err(message, category: :validation)
      end

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

        repo_root = File.expand_path(root)
        repo_root = Master::REPO_ROOT if repo_root == Master::ROOT
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
      # bin/gate's, and while it was missing it fell through to the path,
      # resolved nowhere, and the scan quietly ran over MASTER instead.
      DMESG_FLAGS = {
        "--quiet" => "quiet", "quiet" => "quiet",
        "--normal" => "normal", "normal" => "normal",
        "--verbose" => "verbose", "verbose" => "verbose",
        "--trace" => "trace", "trace" => "trace"
      }.freeze

      # Read by dispatch_fix_in_worktree; never a path.
      INCLUDE_DIRTY_FLAG = "--include-dirty"

      PASS_FLAGS = {
        "--dry-run" => [:apply, false], "preview" => [:apply, false], "dry" => [:apply, false],
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

      def execution_overrides(raw)
        overrides = { autofix_mode: nil, max_files: nil }
        raw.to_s.split(/\s+/).each do |token|
          if (match = AUTOFIX_FLAG.match(token))
            overrides[:autofix_mode] = match[1]
          elsif (match = MAX_FILES_FLAG.match(token))
            overrides[:max_files] = match[1]
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
          elsif DMESG_FLAGS.key?(token.downcase) || token.casecmp?(INCLUDE_DIRTY_FLAG)
            next
          elsif token =~ AUTOFIX_FLAG || token =~ MAX_FILES_FLAG
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

      def run_deliberation(deliberation:, payload:, context:)
        return "deliberation: not configured" unless deliberation

        result = deliberation.review_convergent(payload, context:)
        return result.message if result.err?

        yield result.value!
      end

      # Same persona-panel -> ideation -> cherry-pick pipeline the product
      # critiques (ui/sound/dilla) use, generalized to whatever the scan stage
      # just processed instead of a fixed file list.
      def general_council_critique(deliberation, path)
        files = File.directory?(path) ? snapshot_files(path) : [path]
        return "critique: no reviewable files under #{path}" if files.empty?

        critic = Master::Review::Council::Critique.new(
          mode: :general, agent: deliberation.agent, event_bus: deliberation.bus, files:,
        )
        result = critic.run
        return "critique: #{result.message}" unless result.ok?

        general_critique_report(result.value!, path)
      rescue StandardError => e
        "critique failed: #{e.class}: #{e.message}"
      end

      def general_critique_report(data, path)
        lines = ["critique #{path}: #{Array(data[:cherry_picks]).size} cherry-pick(s) (MASTER council)"]
        Array(data[:feedback]).each do |f|
          first = f[:feedback].to_s.lines.first.to_s.strip
          lines << "  [#{f[:persona]}] #{first}"
        end
        Array(data[:cherry_picks]).each { |p| lines << "  cherry: #{p}" }
        lines << "  harvested: #{data[:harvest]}" if data[:harvest]
        lines.join("\n")
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
