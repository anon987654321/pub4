# frozen_string_literal: true

module Master
  module CLI
    class Pipeline
      # Full singularity pass: posture → aesthetic scan → deep scan → fix → re-scan → optional critique.
      # Progress is OpenBSD dmesg-style (device at bus: detail).
      class Pass
        Result = Data.define(:target, :mode, :sections, :ok, :unit, :failed_stages, :totals) do
          def initialize(totals: {}, **fields) = super(totals:, **fields)

          # "567 findings, 480 after the fix": the deep scan before the fix and the
          # re-scan after it. "complete" alone said nothing about what the pass found
          # or changed.
          def counts
            before, after = totals.values_at(:before, :after)
            return unless before

            after ? "#{before} findings, #{after} after the fix" : "#{before} findings"
          end

          # A section is its title and then its body, one blank line after, with
          # no "#" in front: a terminal is not Markdown, and the title's place
          # at the head of the block is the hierarchy.
          def render
            lines = sections.flat_map { |title, body| [title, body.to_s.chomp, ""] }
            lines << footer
            lines.join("\n")
          end

          # A pass whose fix stage blew up is not "complete". It used to say so
          # anyway, because `ok` was derived from scan text alone and never looked
          # at whether a stage had raised.
          def footer
            base = if failed_stages.any?
                     "#{unit}: incomplete — #{failed_stages.join(", ")} failed"
                   elsif ok
                     "#{unit}: complete"
                   else
                     "#{unit}: complete with open findings"
                   end
            base = "#{base}, #{counts}" if counts
            skipped = Master::Io::QuotaGate.report
            skipped ? "#{base}\n#{skipped}" : base
          end
        end

        # A NameError (NoMethodError included) or TypeError out of a stage is a
        # defect in MASTER, not a finding about the target. Formatting one into
        # the report as "fix failed: NoMethodError: …" and then printing
        # "review0: complete" hid two live crashes for days. Operational failures
        # still degrade to prose so the rest of the pass survives; these do not.
        # ArgumentError is deliberately absent — stages raise it for bad user
        # input, which is a real condition and belongs in the report.
        DEFECT_ERRORS = [NameError, TypeError].freeze

        def initialize(scanner:, fix_loop:, root:, deliberation: nil, bus: nil, review_crew: nil, swarm: nil)
          @failed_stages = []
          @swarm = swarm
          @scanner = scanner
          @fix_loop = fix_loop
          @root = root
          @deliberation = deliberation
          @bus = bus
          @review_crew = review_crew
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

        # No gates stage for a RAILS target. bin/operator gate already runs this
        # pass over RAILS through bin/gate and then `RAILS/gates/runner.rb --all`
        # as its own rails stage, so a runner call here would run every app gate
        # twice in the ladder, and the rendered half needs a browser on the
        # deploy host, where the ladder already reaches it.
        STAGES = %w[fix critique map].freeze
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
        def fix_sections(resolved:, shell:, posture:, aesthetic:)
          sections = [observe_section("observe", "obs0", shell, aesthetic:)]
          unless @apply
            return sections << ["would repair", log_phase("fix0", "preview", "path=#{shell}") { run_fix_preview(resolved) }]
          end

          before = git.head
          sections << ["repair", log_phase("fix0", "converge", "path=#{shell} max_passes=#{posture[:max_fix_passes]}") do
            run_fix(resolved)
          end]
          sections << ["changes", changes_section(before)]
          sections << observe_section("re-observe", "obs1", shell, aesthetic:)
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
        def observe_section(title, unit, shell, aesthetic:)
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

        def target_aliases
          {
            "self" => File.join(@root, "lib"),
            "master" => @root,
            "itself" => @root,
            "." => @root,
            "rails" => Master::RAILS_ROOT,
            "RAILS" => Master::RAILS_ROOT,
            "face" => File.join(@root, "web", "public"),
            "web" => File.join(@root, "web"),
          }
        end

        def resolve_target(raw)
          text = raw.to_s.strip
          text = "." if text.empty? || text.match?(/\A(?:all|everything|the|code|codebase|it|this|that)\z/i)
          aliases = target_aliases
          return aliases[text] if aliases.key?(text)
          if text.match?(%r{\Arails[:/]}i)
            return File.join(Master::RAILS_ROOT, text.sub(%r{\Arails[:/]}i, ""))
          end
          # The pattern admits a leading ../ (bin/gate says ../RAILS from
          # MASTER), but the base here is already the repo root, so expanding
          # the ../ walks OUT of the repo to a sibling that does not exist —
          # and a nonexistent target falls back to scanning MASTER, so the
          # gate's RAILS stage measured the wrong tree and called it RAILS.
          if text.match?(%r{\A(?:\.\./)?RAILS(?:/|\z)})
            return File.expand_path(text.delete_prefix("../"), Master::REPO_ROOT)
          end

          path = File.expand_path(text, @root)
          return path if File.exist?(path)

          File.expand_path(text, Master::REPO_ROOT)
        end

        def shell_target(abs)
          return "self" if abs == File.join(@root, "lib")
          return "master" if abs == @root
          return "rails" if abs == Master::RAILS_ROOT
          return "face" if abs == File.join(@root, "web", "public")
          return "web" if abs == File.join(@root, "web")
          if abs.start_with?("#{Master::RAILS_ROOT}/")
            return "rails/#{abs.delete_prefix("#{Master::RAILS_ROOT}/")}"
          end
          if abs.start_with?("#{@root}/")
            return abs.delete_prefix("#{@root}/")
          end

          abs
        end

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
            "preview total=#{v[:total]} top_rules=#{v[:rules].inspect} top_files=#{v[:files].inspect}"
          else
            Master::Trace::Dmesg.status("fix0", "preview failed: #{result.message}")
            "preview: #{result.message}"
          end
        rescue StandardError => e
          stage_failure("preview", "fix0", e)
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
