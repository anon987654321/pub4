# frozen_string_literal: true

require_relative "../tribunal_feedback"
require_relative "../../review/council/critique"
require_relative "../../fix/execution_trace"
require_relative "../../operator/gate_chain"
require_relative "../../fix/worktree_session"

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

      def dispatch_fix(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, swarm: nil, **_legacy)
        raw = arg_for(ctx).to_s.strip
        apply, critique, aesthetic, only, target = parse_pass_flags(raw)
        # /fix is the operator trace: every event is visible in the same append-only
        # OpenBSD dmesg grammar. An explicit quiet/normal/verbose flag still wins.
        targets = fix_targets(target, root:)
        writes_requested = apply != false && fix_stage_selected?(only)
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
                dependencies: { scanner:, fix_loop:, deliberation:, bus: }
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

          writes_requested = apply != false && fix_stage_selected?(only)
          effective_critique = critique.nil? ? writes_requested : critique

          results = targets.map do |fix_target|
            run_fix_target(
              scanner:, fix_loop:, root:, deliberation:, bus:, swarm:,
              target: fix_target, writes_requested:, effective_critique:, critique:, aesthetic:, only:
            )
          end
          failure = results.find { |result| result.is_a?(Master::Result::Err) }
          next failure if failure

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
          proof_trees: worktree_proof_trees(target, root:)
        )
        return result.summary if result.ok

        Master::Result.err(result.summary, category: :validation)
      end

      def worktree_proof_trees(target, root:)
        tokens = target.to_s.split(/\s+/)
        trees = %w[MASTER RAILS OPENBSD STUDIO]
        return tokens.uniq if tokens.size > 1 && tokens.all? { |token| trees.include?(token) }
        return trees if target.to_s.strip.empty?

        repo_root = File.expand_path(root)
        repo_root = Master::REPO_ROOT if repo_root == Master::ROOT
        [target].filter_map do |value|
          path = File.expand_path(value.to_s, root)
          trees.find do |tree|
            base = File.join(repo_root, tree)
            path == base || path.start_with?("#{base}#{File::SEPARATOR}")
          end
        end.uniq
      end

      def run_fix_target(scanner:, fix_loop:, root:, deliberation:, bus:, swarm:, target:,
                         writes_requested:, effective_critique:, critique:, aesthetic:, only:)
        value = run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                         target:, apply: writes_requested, critique: effective_critique,
                         aesthetic:, only:)
        return value unless writes_requested

        gate_rounds = 0
        gate_status = 0
        gate_changed = []
        loop do
          gate_status, gate_changed = ::Operator::GateChain.verify_fix(target:)
          gate_rounds += 1
          break if gate_status == 0 && gate_changed.empty?
          break if gate_changed.empty? || gate_rounds >= MAX_FIX_GATE_ROUNDS

          Master::Trace::Dmesg.status(
            "gate0", "verification changed #{gate_changed.size} file(s), re-entering /fix"
          )
          value = run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                           target:, apply: true, critique: critique.nil? ? true : critique,
                           aesthetic:, only: "fix")
        end

        if gate_status != 0
          message = "gate verification did not pass (status #{gate_status})"
          Master::Trace::Dmesg.status("gate0", "#{target}: #{message}")
          return Master::Result.err(message, category: :validation)
        end
        if gate_rounds >= MAX_FIX_GATE_ROUNDS && gate_changed.any?
          message = "gate verification reached #{MAX_FIX_GATE_ROUNDS} rounds without a stable tree"
          Master::Trace::Dmesg.status("gate0", "#{target}: #{message}")
          return Master::Result.err(message, category: :validation)
        end

        Master::Trace::Dmesg.status("gate0", "#{target}: delivery verified")
        value
      end

      def execution_trace_scopes(target)
        raw = target.to_s.strip
        return nil if raw.empty?

        trees = %w[MASTER RAILS OPENBSD STUDIO]
        tokens = raw.split(/\s+/)
        return tokens if tokens.size > 1 && tokens.all? { |token| trees.include?(token) }

        tokens.map { |token| token.sub(%r{\A\.\./(?=[A-Z]+(?:/|\z))}, "") }
      end

      def fix_targets(target, root:)
        tokens = target.to_s.split(/\s+/)
        trees = %w[MASTER RAILS OPENBSD STUDIO]
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

      def parse_pass_flags(raw)
        flags = { apply: nil, critique: nil, aesthetic: true, only: nil }
        path_bits = []
        joined_only(raw.split(/\s+/)).each do |token|
          if (flag = PASS_FLAGS[token.downcase])
            flags[flag.first] = flag.last
          elsif DMESG_FLAGS.key?(token.downcase)
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