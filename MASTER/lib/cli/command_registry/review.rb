# frozen_string_literal: true

require_relative "../tribunal_feedback"
require_relative "../../review/council/critique"

module Master
  module CLI
    module CommandRegistry
      module_function

      SNAPSHOT_FILE_BYTES = 8_000
      SNAPSHOT_DIR_FILE_BYTES = 1_200
      SNAPSHOT_DIR_TOTAL_BYTES = 32_000
      SNAPSHOT_DIR_FILE_LIMIT = 40
      SNAPSHOT_EXTENSIONS = %w[.rb .erb .js .yml].freeze
      SNAPSHOT_SKIP_SEGMENTS = %w[
        .git .bundle node_modules vendor tmp log coverage storage cache dist build knowledge public var
      ].freeze

      # /review — the read-only pass. It observes, asks the council and prints
      # the principle map; it changes nothing. The verb that changes the tree is
      # /fix, and it owns the repair.
      def dispatch_review(scanner:, fix_loop:, deliberation:, root:, bus:, ctx: nil, swarm: nil, **_legacy)
        raw = arg_for(ctx).to_s.strip
        apply, critique, aesthetic, only, target = parse_pass_flags(raw)
        with_dmesg_verbosity(raw) do
          run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                   target:, apply: apply || false, critique:, aesthetic:, only: only || "critique,map")
        end
      end

      # /fix — the convergence lifecycle, and the only operation that writes.
      # It observes, critiques, generates and picks between repairs, applies
      # one, validates it and observes again, until the tree converges, stops
      # improving, or hands back a state only a person can settle. `--dry-run`
      # stops after the reading and says what it would take on.
      # /critique — the council stage only. It observes and argues, but does not write.
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
        apply, _critique, aesthetic, _only, target = parse_pass_flags(raw)
        rendered = with_dmesg_verbosity(raw) do
          run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                   target:, apply: apply.nil? || apply, critique: false, aesthetic:, only: "fix")
        end
        return rendered unless apply.nil? || apply

        gate_rounds = 0
        loop do
          status, changed = Operator::GateChain.verify_fix(target:)
          gate_rounds += 1
          break if status == 0 && changed.empty?
          break if changed.empty? || gate_rounds >= MAX_FIX_GATE_ROUNDS

          rendered = [rendered, "gate: verification changed #{changed.size} file(s); re-entering /fix"].join("\n")
          rendered = with_dmesg_verbosity(raw) do
            run_pass({ scanner:, fix_loop:, root:, deliberation:, bus:, swarm: },
                     target:, apply: true, critique: false, aesthetic:, only: "fix")
          end
        end

        if gate_rounds >= MAX_FIX_GATE_ROUNDS
          rendered = [rendered, "fix: gate verification reached #{MAX_FIX_GATE_ROUNDS} rounds without a stable tree"].join("\n")
        end

        return rendered unless Master::Fix::CodeWatch.requested?

        # A run that stopped for newer code continues on it, in this process.
        puts rendered
        Master::Fix::CodeWatch.reexec!(root, "/fix #{raw}")
        rendered
      end

      def run_pass(deps, **call_args)
        Master::CLI::Pipeline::Pass.new(**deps).call(**call_args).render
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

      def with_dmesg_verbosity(raw)
        level = raw.to_s.split(/\s+/).filter_map { |token| DMESG_FLAGS[token.downcase] }.last
        return yield unless level

        Master::Trace::Dmesg.with_verbosity(level) { yield }
      end

      def run_deliberation(deliberation:, payload:, context:)
        return "deliberation: not configured" unless deliberation

        result = deliberation.review_convergent(payload, context:)
        return result.message if result.err?

        yield result.value!
      end

      # The critique stage of /review. Pipeline::Pass calls it.
      def dispatch_critique(deliberation:, root:, ctx: nil)
        arg = arg_for(ctx)
        return "usage: /critique <file|text>" if arg.empty?
        path = expand_or_root(arg, root)
        # respond_to?, not `&.agent` — the safe-navigation operator guards a nil
        # deliberation but not a deliberation that has no agent (lean
        # boot, or a test double), which raised NoMethodError from here.
        has_agent = deliberation.respond_to?(:agent) && deliberation.agent
        return general_council_critique(deliberation, path) if has_agent && File.exist?(path)

        payload = File.exist?(path) ? snapshot_artifact(path) : arg
        run_deliberation(deliberation:, payload:, context: "explicit /critique session") do |feedback|
          TribunalFeedback.new(feedback).render_full
        end
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