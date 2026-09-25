# frozen_string_literal: true

require_relative "../../operator/gate_chain"
require_relative "pass_result"
require_relative "target_resolver"
require_relative "proof"

module Master
  module CLI
    class Pipeline
      class Pass
        include TargetResolver
        include Proof
        # PassResult defines this pass's Result and keeps this file small.

        def initialize(scanner:, fix_loop:, root:, deliberation: nil, bus: nil, swarm: nil)
          @failed_stages = []
          @swarm = swarm
          @scanner = scanner
          @fix_loop = fix_loop
          @root = root
          @deliberation = deliberation
          @bus = bus
          @t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @unit = "review0"
          @observation_totals = {}
          @observe_units = []
        end

        # The stages a caller can ask for by name, in the order they run.
        #
        # `fix` is the whole convergence lifecycle: it observes, repairs what the
        # reading found, and observes again, and the council argues inside the
        # repair. There is no scan stage, because a reading nobody acts on is
        # what this architecture removes — observation is how a fix starts, not
        # an operation of its own.
        #
        # Both readings keep their aesthetic half for a second reason: the RAILS
        # constitutional budget is measured off the aesthetic one, so splitting
        # them would change what that gate compares against.
        SWARM_EXCERPT = 400

        # A writing pass ends in a proof stage: the target tree's own gates, run
        # once after the repair converges. /fix used to report convergence on
        # scanner findings while the gates could still fail, with no way to
        # know. Per-pass proofs are refused — `bin/operator gate` runs the same
        # instruments on its own cadence, and a gates stage inside every pass
        # would double them and blow the pass budget — and the RAILS rendered
        # half stays with the ladder, which already reaches the deploy host's
        # browser.
        STAGES = %w[fix critique map].freeze
        # A NameError or TypeError is a MASTER defect, not a target finding; formatting it into the report hid live crashes.
        DEFECT_ERRORS = [NameError, TypeError].freeze
        STAGE_ALIASES = { "converge" => "fix", "council" => "critique" }.freeze

        def call(target: nil, apply: nil, critique: nil, aesthetic: true, only: nil)
          resolved = resolve_target(target)
          posture = Master::Ground::ModePosture.current(root: @root)
          @only = normalize_stages(only)
          apply = default_apply?(posture) if apply.nil?
          critique = default_critique?(posture, resolved) if critique.nil?
          critique = @only.include?("critique") if @only
          shell = shell_target(resolved)
          @apply = apply

          dmesg_boot(resolved, posture, apply, critique, aesthetic)
          @bus&.publish("review:start", target: resolved, mode: posture[:name], apply:)

          sections = build_sections(resolved:, shell:, posture:, apply:, critique:, aesthetic:)

          ok = pass_ok?(sections)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0).round
          result = Result.new(target: resolved, mode: posture[:name], sections:, ok:, unit: @unit,
                              failed_stages: @failed_stages.dup, totals: totals_for_report)
          Master::Trace::Dmesg.status(@unit, [ok ? "complete" : "incomplete", result.counts, "#{elapsed}s"].compact.join(", ")) if elapsed >= 1
          @bus&.publish("review:complete", target: resolved, apply:, ok:, elapsed_s: elapsed,
                                            failed_stages: @failed_stages)
          result
        end

        private

        def build_sections(resolved:, shell:, posture:, apply:, critique:, aesthetic:)
          # The posture is a section and not a dmesg line: the review0 boot line
          # already names it, and a mode0 line printed the same text the report
          # prints a moment later in the same terminal.
          sections = [["mode", posture_line(posture)]]
          if @unknown_stages&.any?
            sections << ["stages", "unknown stage: #{@unknown_stages.join(", ")} — " \
                                   "--only takes #{STAGES.join(", ")} (council is a spelling of critique)"]
          end
          sections.concat(fix_sections(resolved:, shell:, posture:, aesthetic:)) if run?("fix")
          sections << critique_section(resolved, shell) if critique && run?("critique")
          sections << ["principle map", log_phase("map0", "principle_map", nil) { map_line }] if run?("map")
          sections
        end

        # `--only` names stages; without it every stage runs, which is what
        # /review has always meant. A name that is not a stage runs nothing and
        # says so: silently widening a pass because a flag was misspelled is the
        # failure this flag exists to prevent, and silently narrowing one is the
        # same failure wearing the other coat.
        def normalize_stages(only)
          @unknown_stages = []
          return if only.nil?

          asked = Array(only).flat_map { |s| s.to_s.downcase.split(",") }
                             .map { |s| STAGE_ALIASES.fetch(s.strip, s.strip) }
                             .reject(&:empty?)
          @unknown_stages = asked - STAGES
          asked & STAGES
        end

        def run?(stage) = @only.nil? || @only.include?(stage)

        def critique_section(resolved, shell)
          ["critique", log_phase("crit0", "deliberation", "path=#{shell}") { run_critique(resolved) }]
        end

        # The /fix lifecycle in three sections: what the tree says now, what the
        # repair did about it, and what the tree says after. Read-only, the
        # reading is followed by what a repair would take on rather than by a
        # repair. The council argues inside the repair, not beside it.
        #
        # A writing pass reads its proof first, before the observation's
        # autofix touches the tree, so the proof at the end is judged against
        # what was already failing; and it notes what was dirty then, so what it
        # delivers is only what it changed.
        def fix_sections(resolved:, shell:, posture:, aesthetic:)
          if @apply
            baseline = proof_baseline(resolved)
            @start_dirty = repo_git.changed_paths
          end
          sections = [observe_section(title: "observe", unit: "obs0", shell:, aesthetic:)]
          unless @apply
            return sections << ["would repair", log_phase("fix0", "preview", "path=#{shell}") { run_fix_preview(resolved) }]
          end

          before = git.head
          sections << ["repair", log_phase("fix0", "converge", "path=#{shell} max_passes=#{posture[:max_fix_passes]}") do
            run_fix(resolved)
          end]
          sections << ["changes", changes_section(before)]
          sections << observe_section(title: "re-observe", unit: "obs1", shell:, aesthetic:)
          sections << proof_section(resolved, baseline)
        end

        # A repair that says it repaired and shows nothing asks the operator to
        # go and look. The commits it wrote and the patch they carry belong in
        # the report, under the repair that made them.
        def changes_section(before)
          commits = before ? git.log_between(before) : []
          patch = before ? git.patch_between(before) : ""
          patch = git.working_patch if patch.strip.empty?
          return "nothing changed" if commits.empty? && patch.strip.empty?

          head = commits.empty? ? ["uncommitted, in the working tree"] : commits
          [head.join("\n"), "", colour_patch(patch)].join("\n").rstrip
        end

        # A diff reads by its marks: what left, what arrived, and where. Every
        # other line dims, so the two colours carry the meaning.
        def colour_patch(patch)
          return "" if patch.to_s.strip.empty?
          return patch unless $stdout.tty?

          pastel = Master::Trace::Dmesg.pastel
          patch.lines.map { |line| pastel.decorate(line, *patch_style(line)) }.join
        end

        def patch_style(line)
          case line
          when /\A(?:diff |\+\+\+ |--- )/ then [:bold]
          when /\A@@/ then [:cyan]
          when /\A\+/ then [:green]
          when /\A-/ then [:red]
          else [:dim]
          end
        end

        def git = @git ||= Master::Io::GitOperations.new(@root)

        # One reading, aesthetic half first where it applies. Both halves report
        # under one unit, because they are one look at one tree.
        def observe_section(title:, unit:, shell:, aesthetic:)
          @observe_units << unit
          [title, log_phase(unit, "observe", "path=#{shell}") do
            readings = []
            readings << run_observation("aesthetic #{shell}", unit:) if aesthetic
            readings << run_observation(shell, unit:)
            readings.join("\n")
          end]
        end

        def dmesg_boot(resolved, posture, apply, critique, aesthetic)
          stages = [("aesthetic" if aesthetic && run?("fix")), ("fix" if run?("fix")),
                    ("critique" if critique && run?("critique")), ("map" if run?("map"))].compact.join(", ")
          Master::Trace::Dmesg.attach(@unit, "master0",
            "#{resolved}, #{apply ? "writes" : "read-only"}, #{posture[:name]}, #{stages}")
        end

        def posture_line(_posture)
          Master::Ground::ModePosture.new(root: @root).line
        end

        # The attach line says a stage began and the next one says it ended, as
        # in a dmesg. A stage earns a second line only by taking a second or
        # more. It prints no counts: the only ones at hand measure the word
        # "violation" in the stage's text, not the findings.
        def log_phase(unit, kind, detail)
          Master::Trace::Dmesg.attach(unit, @unit, [kind, detail].compact.join(" "))
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          out = yield
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0).round(1)
          Master::Trace::Dmesg.status(unit, "#{elapsed}s") if elapsed >= 1
          out
        rescue StandardError => e
          Master::Trace::Dmesg.status(unit, "#{e.class}: #{e.message}")
          raise
        end

# Measure unless asked to write.
#
# This returned true, so every route into the pipeline wrote: a flag, a
# slash command, and — the one that matters — a sentence. On 2026-09-11 a
# greeting typed into bin/cli on vm23 ("Hei MASTER … hva er du mest stolt
# av i denne kodebasen?") was routed to /review with apply=yes against
# /home/dev/pub4, which is the checkout the deploy syncs from. It scanned
# 333 of 1109 files before it was interrupted and wrote nothing, and that
# was luck rather than design.
#
# The ladder still writes, because writing is its job: bin/gate says
# --apply in full-fix mode and --no-autofix in scan-only. Making both
# explicit is the point — a caller that wants a write now says so, and
# nothing arrives at one by being misread.

def default_apply?(*) = false

  # MASTER_SCAN_DETERMINISTIC=1 means "no model in this pass", and the
  # council is the largest model call in it. Measured on lib/io, 46 files:
  # the two scan phases cost 32s and this deliberation cost 354.8s, so 91%
  # of a /scan was a critique the caller had not asked for. `bin/gate` then
  # runs /critique again as its own separate stage, which is the tier that
  # is supposed to own it.

  def default_critique?(*) = ENV["MASTER_SCAN_DETERMINISTIC"] != "1"

        def run_observation(arg, unit:)
          # Stash unit so Scanner progress lines attach to this observation.
          if @scanner.respond_to?(:instance_variable_set)
            @scanner.instance_variable_set(:@through_scan_unit, unit)
          end
          # A read-only pass must not write through the observation's mechanical
          # autofix either.
          observe_arg = @apply == false ? "#{arg} --dry-run".strip : arg
          Master::CLI::CommandRegistry.observe(
            scanner: @scanner,
            root: @root,
            ctx: { args: observe_arg },
            on_total: ->(total) { @observation_totals[unit] = total },
          )
        rescue StandardError => e
          stage_failure("observe", unit, e)
        end

        def pass_ok?(sections)
          @failed_stages.empty? && sections.none? do |title, body|
            title.include?("observe") && body.to_s.match?(/\berror\b|\bcritical\b/i) && body.to_s.match?(/\d{2,}\s+finding/i)
          end
        end

        def totals_for_report
          before, after = @observe_units.first, @observe_units.last
          return {} unless before

          { before: @observation_totals[before], after: (@observation_totals[after] if after != before) }.compact
        end

        def run_fix(abs)
          result = @fix_loop.run(abs, requested: true)
          msg = result.ok? ? result.value!.to_s : "fix: #{result.message}"
          Master::Trace::Dmesg.status("fix0", result.ok? ? msg[0, 80] : "failed: #{result.message}")
          msg
        rescue StandardError => e
          stage_failure("fix", "fix0", e)
        end

        # One place decides what a stage exception means. Defects propagate;
        # everything else becomes a reported failure that also marks the run
        # incomplete, so no stage can crash quietly into a "complete" footer.
        def stage_failure(label, unit, error)
          raise error if DEFECT_ERRORS.any? { |klass| error.is_a?(klass) }

          @failed_stages << label
          Master::Trace::Dmesg.status(unit, "#{error.class}: #{error.message}")
          "#{label} failed: #{error.class}: #{error.message}"
        end

        def run_fix_preview(abs)
          result = @fix_loop.preview(abs)
          if result.ok?
            v = result.value!
            Master::Trace::Dmesg.status("fix0", "preview, #{v[:total]} findings")
            preview_lines(v)
          else
            Master::Trace::Dmesg.status("fix0", "preview failed: #{result.message}")
            "preview: #{result.message}"
          end
        rescue StandardError => e
          stage_failure("preview", "fix0", e)
        end

        # What the repair would take on, as two lines a person reads rather than
        # two Ruby hashes printed with #inspect. The dump ran past the width of a
        # terminal, so the counts that matter were wherever the wrap happened to
        # put them, and it named every file by its full path when the pass has
        # already said which tree it is in.
        PREVIEW_SHOWN = 6

        def preview_lines(value)
          total = value[:total].to_i
          files = value[:files].to_h.transform_keys { |path| File.basename(path.to_s) }
          [
            "preview: #{total} #{total == 1 ? 'repair' : 'repairs'}",
            preview_row("rules", value[:rules]),
            preview_row("files", files),
          ].compact.join("\n")
        end

        def preview_row(label, counts)
          counts = counts.to_h
          return if counts.empty?

          shown = counts.first(PREVIEW_SHOWN).map { |name, count| "#{name} #{count}" }
          rest = counts.size - shown.size
          line = "preview #{label}: #{shown.join(', ')}"
          rest.positive? ? "#{line}, and #{rest} more" : line
        end

        def run_critique(abs)
          return "critique: deliberation not configured" unless @deliberation

          [swarm_review(abs), deliberation_critique(abs)].compact.join("\n")
        end

        # Review::Swarm::Coordinator is built under MASTER_FULL_BOOT=1, placed in
        # the bundle as `swarm:`, and until now read by nothing: 546 lines of
        # analyst/reviewer fan-out with a vote engine sitting in the boot graph,
        # 99 of 278 body lines unreached. It runs here because a per-file reading
        # is what `analyse_and_review` is for, and ahead of the deliberation
        # because the council argues better with one in front of it. A lean boot
        # passes nil and this returns nil, so the default pass is unchanged.
        def swarm_review(abs)
          return unless @swarm && File.file?(abs)

          result = @swarm.analyse_and_review(file_path: abs, code: File.read(abs))
          return "swarm: #{result.message}" unless result.ok?

          reading = result.value!
          verdict = reading[:approved] ? "approved" : "not approved"
          "swarm: #{verdict} — #{reading[:review].to_s.gsub(/\s+/, " ")[0, SWARM_EXCERPT]}"
        rescue StandardError => e
          stage_failure("swarm", "crit0", e)
        end

        def deliberation_critique(abs)
          Master::CLI::CommandRegistry.dispatch_critique(
            deliberation: @deliberation,
            root: @root,
            ctx: { args: abs },
          )
        rescue StandardError => e
          stage_failure("critique", "crit0", e)
        end

        def map_line
          Master::Ground::Map::Principle.load(root: @root).summary_line
        rescue StandardError => e
          stage_failure("principle map", "map0", e)
        end
      end
    end
  end
end
