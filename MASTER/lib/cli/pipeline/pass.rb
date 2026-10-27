# frozen_string_literal: true

require_relative "../../operator/check_chain"
require_relative "../../fix/outcome_policy"
require_relative "pass_result"
require_relative "target_resolver"
require_relative "proof"
require_relative "reobservation"
require_relative "residual"

module Master
  module CLI
    class Pipeline
      class Pass
        include TargetResolver
        include Proof
        # PassResult defines this pass's Result and keeps this file small.

        # Whether a pass convenes the council when no flag says: only when it is asked for (PassClock), a
        # model is in play, and the pass writes or reads for a purpose.
        def self.critique_by_default?(apply: nil)
          apply != false && Master::Review::LLMDispatcher::PassClock.council_enabled? &&
            ENV["MASTER_SCAN_DETERMINISTIC"] != "1"
        end

        # Endings that stop a run without saying its delivered work was wrong. A run that committed
        # verified fixes and then plateaued or ran out of time did useful work, and calling it a
        # failure hid every fix /fix ever landed behind the same verdict as a crash.
        PARTIAL_ENDINGS = Master::Fix::OutcomePolicy::PARTIAL_ENDINGS

        # :done, :partial, :incomplete or :failed, from the loop's result and the commits it made.
        # ending: the loop's own terminal state when it reports one; the message is only parsed
        # for a loop that does not.
        def self.fix_outcome(ok:, msg:, delivered:, ending: nil)
          Master::Fix::OutcomePolicy.workflow_outcome(ok:, msg:, delivered:, ending:)
        end

        # The run in one line: how it ended, what it delivered, the findings before and after, the
        # proof's verdict with the hard and soft checks it left red, and the gaps.
        def self.scorecard(outcome:, delivered:, counts: [], proof: nil, gaps: 0)
          before, after = counts
          findings = after && before ? "#{after} finding(s), was #{before}" : "#{before || after || "?"} finding(s)"
          ["fix #{final_outcome(outcome, proof)}", "#{delivered} commit(s) delivered", findings,
           *proof_parts(proof), "#{gaps} gap(s)"].join(" · ")
        end

        # A run that reached DONE while a hard check is still red has not finished the app.
        def self.final_outcome(outcome, proof)
          outcome == :done && Array(proof&.fetch(:hard, nil)).any? ? :partial : outcome
        end

        def self.proof_parts(proof)
          return ["no proof ran"] unless proof

          hard, soft, unmeasured = proof.values_at(:hard, :soft, :unmeasured).map { |checks| Array(checks) }
          [proof[:verdict], "hard red #{hard.size}#{" (#{hard.first(3).join(", ")})" if hard.any?}",
           "soft red #{soft.size}", ("unmeasured #{unmeasured.size}" if unmeasured.any?)].compact
        end

        def self.fix_ending(msg) = Master::Fix::OutcomePolicy.extract_state(msg)

        def self.halted?(ending) = Master::Fix::OutcomePolicy.halted?(ending)

        def initialize(scanner:, fix_loop:, root:, deliberation: nil, bus: nil, swarm: nil)
          @failed_stages = []
          @causes = {}
          @swarm = swarm
          @scanner = scanner
          @fix_loop = fix_loop
          @root = root
          @deliberation = deliberation
          @bus = bus
          @t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @unit = "review0"
          @observation_totals = {}
          @observed_counts = {}
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
        # them would change what that check compares against.
        SWARM_EXCERPT = 400

        # A writing pass ends in a proof stage: the target tree's own checks, run
        # once after the repair converges. /fix used to report convergence on
        # scanner findings while the checks could still fail, with no way to
        # know. Per-pass proofs are refused — `bin/operator check` runs the same
        # instruments on its own cadence, and a checks stage inside every pass
        # would double them and blow the pass budget — and the RAILS rendered
        # half stays with the ladder, which already reaches the deploy host's
        # browser.
        STAGES = %w[fix critique map].freeze
        # A NameError or TypeError is a MASTER defect, not a target finding; formatting it into the report hid live crashes.
        DEFECT_ERRORS = [NameError, TypeError].freeze
        STAGE_ALIASES = { "converge" => "fix", "council" => "critique" }.freeze

        def call(target: nil, apply: nil, critique: nil, aesthetic: true, only: nil, cancellation: nil)
          resolved = resolve_target(target)
          @resolved = resolved
          @cancellation = cancellation
          posture = Master::Ground::ModePosture.current(root: @root)
          @only = normalize_stages(only)
          apply = default_apply?(posture) if apply.nil?
          critique = default_critique?(posture, resolved, apply:) if critique.nil?
          critique = @only.include?("critique") if @only
          shell = shell_target(resolved)
          @apply = apply
          @critique_enabled = critique

          dmesg_boot(resolved, posture, apply, critique, aesthetic)
          @bus&.publish("review:start", target: resolved, mode: posture[:name], apply:)

          sections = build_sections(resolved:, shell:, posture:, apply:, critique:, aesthetic:)

          ok = pass_ok?(sections)
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0).round
          result = Result.new(target: resolved, mode: posture[:name], sections:, ok:, unit: @unit,
                              failed_stages: @failed_stages.dup, totals: totals_for_report, causes: @causes.dup)
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
          sections.concat(guarded_fix_sections(resolved:, shell:, posture:, aesthetic:, critique:)) if run?("fix")
          sections << ["scorecard", scorecard_line] if @scored
          sections << ["council", COUNCIL_OFFER] if offer_council?(critique)
          sections << critique_section(resolved, shell) if critique && run?("critique") && !run?("fix")
          sections << ["principle map", log_phase("map0", "principle_map", nil) { map_line }] if run?("map")
          sections
        end

        COUNCIL_OFFER = "not run during /fix; /critique convenes it on this result"

        def scorecard_line
          counts = @observation_totals.values_at("obs0", "obs1")
          line = self.class.scorecard(**@scored, counts:, proof: @proof, gaps: fix_gaps)
          Master::Trace::Dmesg.status("fix0", line)
          Residual.write(target: File.basename(@resolved.to_s), scorecard: line, proof: @proof,
                         named: Master::Fix::CheckFocus.named)
          line
        end

        # :reek:ManualDispatch -- test doubles for the fix loop do not count gaps
        def fix_gaps = @fix_loop.respond_to?(:gap_count) ? @fix_loop.gap_count : 0

        # Offered after a /fix that read the tree and did not convene the council.
        def offer_council?(critique) = run?("fix") && @apply && !critique && !@failed_stages.include?("instruments")

        # A run whose instruments are broken reports thousands of files as clean or as scan errors. Ask
        # first, in seconds, and stop with the reason, before the baseline suites and the scan spend an hour.
        # :reek:ManualDispatch -- a loop without the check, as a test double has none, is not a broken one.
        def guarded_fix_sections(**)
          broken = @fix_loop.respond_to?(:instrument_failures) ? @fix_loop.instrument_failures : []
          return fix_sections(**) if broken.empty?

          reason = broken.join("; ")
          fail_stage("instruments", reason)
          Master::Trace::Dmesg.status("fix0", "instruments unavailable, nothing was read: #{reason}"[0, 220])
          listed = broken.map { |line| "- #{line}" }.join("\n")
          [["instruments", "fix instruments unavailable, nothing was read:\n#{listed}"]]
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

        # The canonical /fix lifecycle is one pass: observe, council critique,
        # repair, re-observe, prove. In dry-run mode the repair becomes a preview.
        # Review and critique remain compatibility views over this same pipeline.
        #
        # A writing pass reads its proof first, before the observation's
        # autofix touches the tree, so the proof at the end is judged against
        # what was already failing; and it notes what was dirty then, so what it
        # delivers is only what it changed.
        def fix_sections(resolved:, shell:, posture:, aesthetic:, critique:)
          if @apply
            baseline = proof_baseline(resolved)
            @start_dirty = repo_git.changed_paths
          end
          run_aesthetic = aesthetic && posture[:scan_profile].to_s != "full"
          sections = [observe_section(title: "observe", unit: "obs0", shell:, aesthetic: run_aesthetic)]
          if critique && !(@only && !@only.include?("critique"))
            sections << critique_section(resolved, shell)
          end
          unless @apply
            # MASTER_FIX_PREVIEW=0: a check tier's read-only pass wants the reading alone.
            return sections if ENV["MASTER_FIX_PREVIEW"] == "0"

            return sections << ["would repair", log_phase("fix0", "preview", "path=#{shell}") { run_fix_preview(resolved) }]
          end

          before = git.head
          sections << ["repair", log_phase("fix0", "converge", "path #{shell}, max #{posture[:max_fix_passes]} passes") do
            run_fix(resolved)
          end]
          @repair_before = before
          changes = changes_section(before)
          sections << ["changes", changes]
          unproven = repair_unproven(changes)
          return sections << ["proof", unproven] if unproven

          sections << reobserve_section(before:, resolved:, shell:, aesthetic: run_aesthetic)
          return sections << ["proof", NOTHING_DELIVERED] if nothing_delivered?(before)

          sections << proof_section(resolved, baseline)
        ensure
          put_back_autofix if @apply && !@fix_crashed
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
          [title, log_phase(unit, "observe", "path #{shell}") do
            readings = []
            readings << run_observation("aesthetic #{shell}", unit:) if aesthetic
            readings << run_observation(shell, unit:)
            readings.join("\n")
          end]
        end

        REPAIR_UNPROVEN = "skipped: the repair failed and changed nothing, so there is nothing to read again or prove"

        # A repair that died before writing leaves the tree as the first reading saw it. The diff
        # text alone cannot say so in the shared checkout, where other writers' edits always show;
        # what this run delivered is its commits and its autofix writes.
        def repair_failed_without_changes?(changes)
          return false unless @failed_stages.include?("fix")

          changes == "nothing changed" || (@repair_before && nothing_delivered?(@repair_before))
        end

        REPAIR_CRASHED = "skipped: the repair crashed, so nothing after it reads, proves or delivers the tree"

        # A crashed repair proves nothing, so the observation's autofix bytes it would have carried go back.
        def discard_unproven_writes = [REPAIR_CRASHED, *put_back_autofix].join("\n")

        # The observation's autofix bytes the run did not deliver go back on every ending: a red proof or
        # a failed repair proves nothing, and STUDIO's red proof left 19 files of them in the tree. A
        # delivered file is committed and so untouched. Only uncommitted files still holding exactly
        # those bytes; a later edit is another writer's. Answers the lines it printed.
        def put_back_autofix
          uncommitted = repo_git.changed_paths.map { |path| File.join(repo_top, path) }
          reverted, left = Master::Fix::AutofixGuard.revert_written!(uncommitted)

          named = left.first(5).join(", ")
          notes = [("put back #{reverted.size} file(s) the autofix wrote" if reverted.any?),
                   ("left #{left.size} file(s) changed since the autofix wrote them: #{named}" if left.any?)]
          notes.compact.each { |line| Master::Trace::Dmesg.status("fix0", line[0, 300]) }
        end

        # The proof section's text when the repair leaves nothing to prove, else nil.
        def repair_unproven(changes)
          return REPAIR_UNPROVEN if repair_failed_without_changes?(changes)

          discard_unproven_writes if @fix_crashed
        end

        def repo_top = Master::REPO_ROOT

        NOTHING_DELIVERED = "skipped: the run committed nothing and its autofix left nothing, so the baseline stands"

        # In the shared checkout the working tree always holds someone's changes, so "nothing changed"
        # rarely reads true; what this run delivered is its commits and its autofix writes.
        def nothing_delivered?(before)
          git.log_between(before).empty? && Master::Fix::AutofixGuard.written.none? do |path|
            Master::Fix::AutofixGuard.still_as_written?(path)
          end
        end

        # The second reading of a repair covers the files the repair changed; see Reobservation.
        def reobserve_section(before:, resolved:, shell:, aesthetic:)
          scope = reobservation&.scope(before, resolved) unless aesthetic
          return observe_section(title: "re-observe", unit: "obs1", shell:, aesthetic:) unless scope

          ["re-observe", reread(scope, shell)]
        end

        def reread(scope, shell)
          @observe_units << "obs1"

          log_phase("obs1", "observe", "path #{shell}, #{scope.changed.size} changed") do
            @observed_counts["obs1"] = {}
            reading =scope.files.empty? ? "" : run_observation(shell, unit: "obs1", files: scope.files)
            @observation_totals["obs1"] = reobservation.total(scope.changed, @observed_counts["obs1"])
            note = "re-read #{scope.files.size} changed files; the others carry obs0's counts"
            [note, reading].reject(&:empty?).join("\n")
          end
        end

        # Nil until a first reading has left its total and its counts to carry forward.
        def reobservation
          return unless @observation_totals.key?("obs0") && @observed_counts.key?("obs0")

          Reobservation.new(
            git: repo_git,
            root: @root,
            first_total: @observation_totals["obs0"],
            first_counts: @observed_counts["obs0"],
          )
        end

        def dmesg_boot(resolved, posture, apply, critique, aesthetic)
          stages = [("aesthetic" if aesthetic && run?("fix")), ("fix" if run?("fix")),
                    ("critique" if critique && run?("critique")), ("map" if run?("map"))].compact.join(", ")
          Master::Trace::Dmesg.attach(@unit, "master0",
            "#{resolved}, #{apply ? "writes" : "read-only"}, #{stages}")
          Master::Trace::Dmesg.attach(
            "mode0", @unit,
            Master::Ground::ModePosture.new(root: @root).line(posture)
          )
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
# The ladder still writes, because writing is its job: bin/check --ladder says
# --apply in full-fix mode and --no-autofix in scan-only. Making both
# explicit is the point — a caller that wants a write now says so, and
# nothing arrives at one by being misread.

def default_apply?(*) = false

  # The council is the largest model call in a pass: measured on lib/io, 46 files, the two scan phases
  # cost 32s and this deliberation cost 354.8s. It runs only when asked, by --critique or
  # MASTER_FIX_COUNCIL=1, and the report ends with an offer to convene it.

  def default_critique?(*, apply: nil) = self.class.critique_by_default?(apply:)

        def run_observation(arg, unit:, files: nil)
          # Stash unit so Scanner progress lines attach to this observation.
          if @scanner.respond_to?(:instance_variable_set)
            @scanner.instance_variable_set(:@through_scan_unit, unit)
          end

          # A read-only pass must not write through the observation's mechanical
          # autofix either.
          observe_arg = @apply == false ? "#{arg} --dry-run".strip : arg
          context = { args: observe_arg, on_counts: ->(counts) { @observed_counts[unit] = counts } }
          on_total = ->(total) { @observation_totals[unit] = total }

          registry = Master::CLI::CommandRegistry
          reading = { scanner: @scanner, root: @root, on_total: }
          return registry.observe_files(**reading, context: context.merge(files:)) if files

          registry.observe(**reading, ctx: context)
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

        # Read the canonical FixLoop state vocabulary instead of maintaining
        # a second list of failure-shaped terminal strings here. Only DONE
        # means this lifecycle proved completion; every other terminal is a halt.
        def non_success_fix_terminal?(message)
          state = message.to_s.match(/\A([A-Z_]+):/)&.captures&.first&.downcase&.to_sym
          state && state != :done && Master::Fix::FixLoop::TERMINAL_STATES.include?(state)
        end

        def run_fix_loop(abs)
          parameters = @fix_loop.method(:run).parameters
          supports_cancellation = parameters.any? do |kind, name|
            kind == :keyrest || (%i[key keyreq].include?(kind) && name == :cancellation)
          end
          options = { requested: true }
          options[:cancellation] = @cancellation if supports_cancellation
          @fix_loop.run(abs, **options)
        end

        def run_fix(abs)
          # On vm23 the control plane shares this process and owns Git sync + deploy.
          # Claim the same execution slot around an interactive /fix so the control
          # plane cannot fetch, rebase or deploy while the fix loop is mutating main.
          claimed = Master::Ops::LoopOwner.with_claim("fix") do
            head = git.head
            result = run_fix_loop(abs)
            fix_verdict(result, fix_commits_since(head))
          end
          return claimed unless claimed == false

          holder = Master::Ops::LoopOwner.active || {}
          fail_stage("fix", "loop slot held by #{holder["loop"]} pid #{holder["pid"]}")
          Master::Trace::Dmesg.status("fix0", "failed, loop slot held by #{holder["loop"]} pid #{holder["pid"]}; no repair ran")
          "fix failed: loop slot held by #{holder["loop"]} pid #{holder["pid"]}"
        rescue StandardError => e
          @fix_crashed = true
          stage_failure("fix", "fix0", e)
        end

        def fix_verdict(result, delivered)
          ok = result.ok?
          @fix_crashed = true if !ok && result.category == :crash
          msg = ok ? result.value!.to_s : result.message.to_s
          outcome = self.class.fix_outcome(ok:, msg:, delivered:, ending: loop_ending)
          @scored = { outcome:, delivered: }
          return fix_done(msg) if outcome == :done
          return fix_partial(msg, delivered) if outcome == :partial

          fail_stage("fix", msg)
          Master::Trace::Dmesg.status("fix0", "#{outcome}, #{msg[0, 120]}")
          "fix #{outcome}: #{msg}"
        end

        # :reek:ManualDispatch -- test doubles for the fix loop do not report a terminal state
        def loop_ending = @fix_loop.respond_to?(:last_terminal_state) ? @fix_loop.last_terminal_state : nil

        def fix_done(msg)
          Master::Trace::Dmesg.status("fix0", msg[0, 120])
          msg
        end

        def fix_partial(msg, delivered)
          Master::Trace::Dmesg.status("fix0", "partial, #{delivered} commit(s) delivered; stopped #{msg[0, 100]}")
          "fix partial: #{delivered} verified commit(s) delivered; stopped: #{msg}"
        end

        # Commits /fix made since head: a Fix_loop: subject and MASTER's trailer together, because
        # other writers in the shared checkout use the same trailer.
        def fix_commits_since(head)
          return 0 if head.to_s.empty?

          # Committer subjects are deliberately lowercase (for example,
          # "fix_loop: pass 1"). Git's --grep is case-sensitive unless told
          # otherwise; the old Fix_loop spelling counted zero of those commits.
          greps = ["--all-match", "--regexp-ignore-case", "--grep=^fix_loop:",
                   "--grep=#{Master::Core::World::COMMIT_TRAILER}"]
          command = ["git", "-C", @root.to_s, "rev-list", "--count", *greps, "#{head}..HEAD"]
          out, status = Master::Io::Exec.capture2e(*command)
          status.success? ? out.to_i : 0
        end

        # One place decides what a stage exception means. Defects propagate;
        # everything else becomes a reported failure that also marks the run
        # incomplete, so no stage can crash quietly into a "complete" footer.
        def stage_failure(label, unit, error)
          raise error if DEFECT_ERRORS.any? { |klass| error.is_a?(klass) }

          fail_stage(label, "#{error.class}: #{error.message}")
          Master::Trace::Dmesg.status(unit, "#{error.class}: #{error.message}")
          "#{label} failed: #{error.class}: #{error.message}"
        end

        # Marks a stage failed and keeps its first reason, which the report footer prints.
        def fail_stage(label, cause)
          @failed_stages << label unless @failed_stages.include?(label)
          (@causes ||= {})[label] ||= cause.to_s.strip[0, 240]
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
          [blocker_line(value[:blockers]), *finding_lines(value)].compact.join("\n")
        end
        # The preview's wording, read from a preview's value alone.
        public :preview_lines

        # --plan: the files a red check names come first, because the run would repair them first.
        def blocker_line(blockers)
          named = Array(blockers)
          return if named.empty?

          shown = named.first(PREVIEW_SHOWN).join(", ")
          "preview blockers: #{named.size} file(s) named by a red check, first: #{shown}"
        end

        def finding_lines(value) = (summary_rows(value) + detail_rows(value)).compact.join("\n")

        def summary_rows(value)
          [total_line(value[:total].to_i), semantic_note(value[:gaps]), preview_row("laws", value[:laws])]
        end

        def detail_rows(value)
          files = value[:files].to_h.transform_keys { |path| File.basename(path.to_s) }
          order = Array(value[:transformation_order]).join(" > ")
          [preview_row("files", files), preview_structure_row(Array(value[:structure])),
           preview_row("transformations", { "order" => order })]
        end

        # The repair's queue: every finding at warning or above once conflicts are resolved, one per place, where
        # the observation's report groups findings by law and message. "repairs" read as work already decided.
        def total_line(total) = "preview: #{total} #{total == 1 ? "finding" : "findings"} at warning or above to repair"

        def semantic_note(gaps)
          gaps = (gaps || {}).to_h
          inconclusive = gaps.fetch(:semantic_inconclusive, gaps.fetch("semantic_inconclusive", {})).to_h
          pending = gaps.fetch(:semantic_pending, gaps.fetch("semantic_pending", {})).to_h
          parts = []
          parts << "INCONCLUSIVE #{inconclusive.size} file(s)" if inconclusive.any?
          parts << "PENDING #{pending.size} file(s)" if pending.any?
          "preview semantic: #{parts.join("; ")}; model-backed coverage incomplete" if parts.any?
        end

        def preview_structure_row(structure)
          return "preview structure: 0 problem(s)" if structure.empty?

          shown = structure.first(PREVIEW_SHOWN).map do |problem|
            operations = Array(problem[:candidate_operations]).join("/")
            "#{problem[:problem_id]} #{operations}"
          end
          rest = structure.size - shown.size
          line = "preview structure: #{shown.join(', ')}"
          rest.positive? ? "#{line}, and #{rest} more problem(s)" : line
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
          unless @deliberation
            fail_stage("critique", "deliberation not configured")
            Master::Trace::Dmesg.status("crit0", "failed, deliberation not configured")
            return "critique failed: deliberation not configured"
          end

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
          result = Master::CLI::CouncilCrit.run(
            root: abs,
            deliberation: @deliberation,
            bus: @bus,
          )
          return result.value! if result.ok?

          fail_stage("critique", result.message)
          Master::Trace::Dmesg.status("crit0", "failed, #{result.message}")
          "critique failed: #{result.message}"
        rescue StandardError => e
          stage_failure("critique", "crit0", e)
        end

        def map_line
          Master::Ground::Map::LawMap.load(root: @root).summary_line
        rescue StandardError => e
          stage_failure("principle map", "map0", e)
        end
      end
    end
  end
end
