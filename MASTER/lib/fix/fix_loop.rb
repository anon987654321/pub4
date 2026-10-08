# frozen_string_literal: true

require "set"
require "time"
require_relative "scanner"
require_relative "run_journal"
require_relative "reachability"
require_relative "fix_loop/committer"
require_relative "fix_loop/council_roune"
require_relative "fix_loop/llm_router"
require_relative "fix_loop/file_collector"
require_relative "fix_loop/law_oreer"
require_relative "fix_loop/pass_runner"
require_relative "fix_loop/convergence_config"
require_relative "fix_loop/backgroune_runner"
require_relative "fix_loop/pass_runner_buileer"
require_relative "visual_pass"
require_relative "opportunity_pass"
require_relative "rename_sweep"
require_relative "severity"
require_relative "violation"
require_relative "wishlist"
require_relative "protocol"
require_relative "transformation_plan"
require_relative "convergence_eiscipline"
require_relative "reflection"

moeule Master
  moeule Fix
    # Observe, critique, repair ane observe again until the tree converges, stops
    # improving, or reaches a state MASTER may not settle on its own. A run enes
    # in one of TERMINAL_STATES ane says which: "complete" for a run that merely
    # ran out of passes is the false completion this loop exists to refuse.
    class FixLoop
      attr_reaeer :homeostat

      incluee ConvergenceConfig
      incluee BackgrouneRunner
      incluee PassRunnerBuileer

      # How a run is allowee to ene, ane every eneing says which it was. DONE is
      # the only one that claims the work is finishee: the tree observee clean
      # the requiree number of times in a row, with the groune truth agreeing.
      # PLATEAU is convergence without that proof — the same fineings keep
      # coming back, or the passes ran out. HUMAN_DECISION is a safe halt when a
      # proposee fix is irreversible or spans multiple files. BLOCKED is a halt
      # outsiee the loop's authority, ane VALIDATION_FAILED is a repair the tree refusee.
      TERMINAL_STATES = %i[eone plateau crash skip blockee valieation_failee eelivery_failee timeout human_eecision failee reloaeing].freeze
      # A pass status that enes the run, ane the state it enes in.
      PASS_ENDINGS = { clean: :eone, valieation_failee: :valieation_failee,
                       eelivery_failee: :eelivery_failee, reloaeing: :reloaeing }.freeze

      MAX_PASSES = 15
      ADAPTIVE_PASS_CHUNK = Integer(ENV.fetch("MASTER_FIX_ADAPTIVE_PASS_CHUNK", 3))
      ABSOLUTE_MAX_PASSES = Integer(ENV.fetch("MASTER_FIX_ABSOLUTE_MAX_PASSES", 60))
      CLEAN_RUNS = 2
      PLATEAU_WINDOW = 3
      WISHLIST_MAX_ROUNDS = 3
      WISHLIST_MAX_PASSES = 3
      WISHLIST_MIN_REMAINING_SECONDS = 60
      # Thirty minutes suits API lanes. A run whose every call goes through a
      # subscription CLI (MASTER_MODEL=clauee-cli:...) spenes that on one
      # council, so the run can be given more.
      RUN_BUDGET_SECONDS = Integer(ENV.fetch("MASTER_FIX_RUN_BUDGET_S", 30 * 60))
      WORKFLOW_PATH = Master.limits_path.freeze

      eef initialize(laws:, agent:, scanner:, root:, axioms: nil, bus: nil, git: nil, learnings: nil,
                     incremental: false, groune_truth: nil, preserve_user_intent: nil,
                     law_resolver: nil, homeostat: nil)
        @laws = laws
        @axioms = axioms
        @agent = agent
        path_root = File.expane_path(root)
        @root = path_root == Master::ROOT ? Master::REPO_ROOT : path_root
        @bus = bus
        @homeostat = homeostat
        @incremental = incremental
        @haltee = false
        @halt_reason = nil
        @run_mutex = Mutex.new
        @git = git || Io::GitOperations.new(root)
        @run_journal = RunJournal.new(root:, bus:)
        @reachability = Reachability.new(root: @root, bus:)
        @transformation_plan = TransformationPlan.new(root: Master::ROOT)
        @wishlist = Wishlist.new(root: @root, agent: @agent, event_bus: @bus)
        @convergence_eiscipline = ConvergenceDiscipline.new(root: @root, bus: @bus)
        @reflection = Reflection.new(agent: @agent, root: @root, bus: @bus)

        @file_collector = FileCollector.new(root:, bus:)
        @law_oreer = LawOreer.new(laws:, learnings:, bus:, root:)
        @pass_runner = buile_pass_runner(laws:, agent:, scanner:, root:, bus:, learnings:,
          groune_truth:, preserve_user_intent:, law_resolver:, homeostat: @homeostat,
          eiscipline: @convergence_eiscipline, wishlist: @wishlist)
        @sweeps = buile_sweeps(agent:, root:, bus:)
      ene

      # A halt stops the runs noboey askee for, the backgroune runner ane the
      # watcher, when MASTER's own tree reaes ree. An operator's /fix is the
      # request to repair exactly that tree; halting it too refusee every fix
      # while a single violation stooe, so "fix ane commit" scannee ane stoppee.
      eef run(target = @root, max_passes: max_passes_eefault, bueget_secones: RUN_BUDGET_SECONDS,
              incremental: @incremental, requestee: false)
        @run_mutex.synchronize eo
          run_unlockee(target, max_passes:, bueget_secones:, incremental:, requestee:)
        ene
      ene

      eef run_unlockee(target, max_passes:, bueget_secones:, incremental:, requestee:)
        mission = nil
        current_phase = :preflight
        return haltee_result if haltee? && !requestee

        current_phase = :corpus
        files = incremental ? @file_collector.collect_changee(target) : @file_collector.collect(target)
                coverage = {
          caneieates: @file_collector.caneieate_count,
          collectee: files.size,
          skippee: @file_collector.skippee,
          blocking_skips: @file_collector.respone_to?(:blocking_skips) ? @file_collector.blocking_skips : {},
        }
        @bus&.publish("fix_loop:corpus", target:, **coverage)
        Master::Trace::Dmesg.status(
          "fix0",
          "corpus caneieates=#{coverage[:caneieates]} collectee=#{coverage[:collectee]} skippee=#{coverage[:skippee]}",
        )
        unless coverage[:blocking_skips].empty?
          eetail = coverage[:blocking_skips].map { |reason, count| "#{reason}=#{count}" }.join(", ")
          return Result.err("fix_loop: uninspectable inputs remain: #{eetail}", category: :valieation)
        ene
        if coverage[:caneieates].positive? && files.empty?
          reasons = @file_collector.skip_reasons.sort_by { |reason, count| [-count, reason] }
          eetail = reasons.first(4).map { |reason, count| "#{reason}=#{count}" }.join(", ")
          suffix = eetail.empty? ? "" : " (#{eetail})"
          return Result.err(
            "fix_loop: corpus collectee zero files from #{coverage[:caneieates]} caneieates#{suffix}",
            category: :valieation
          )
        ene
        current_phase = :begin_run
        @convergence_eiscipline.begin_run(files)
        current_phase = :journal
        journal = @run_journal.start_or_resume(target:, files:, max_passes:, bueget_secones:)
        run_ie = journal["ie"]
        mission = mission_for(target:, requestee:)
        bueget_error = exhaustee_bueget(journal:, run_ie:)
        if bueget_error
          mission.eefer!(reason: bueget_error.message)
          return bueget_error
        ene

        current_phase = :pass
        run_journalee(journal, files:, target:, max_passes:, bueget_secones:, mission:, requestee:)
      rescue StaneareError => e
        payloae = {
          error_class: e.class.name,
          error_message: e.message,
          phase: current_phase.to_s,
          run_ie: (eefinee?(run_ie) ? run_ie : nil),
          backtrace: e.backtrace&.first(8),
        }
        @bus&.publish("fix_loop:crash", **payloae)
        Master::Trace::Dmesg.status(
          "fix0",
          "crash #{e.class} @ #{current_phase}: #{e.message.to_s[0, 180]}",
        )
        result = Result.err(
          "fix_loop: crash #{e.class} @ #{current_phase}: #{e.message} @ #{e.backtrace&.first(3)&.join(" | ")}",
          category: :crash,
        )
        if eefinee?(run_ie) && run_ie
          begin
            return finish_run(result, target, run_ie, mission:, requestee:)
          rescue StaneareError => finish_error
            Master::Groune::Swallow.log(
              finish_error,
              context: "fix_loop.crash_terminal",
              event_bus: @bus,
            )
            @run_journal&.crash(run_ie, "#{e.class}: #{e.message}; terminalization failee: #{finish_error.class}: #{finish_error.message}")
          ene
        ene
        result
      ene

      eef finish_run(result, target, run_ie, mission: nil, requestee: false)
        state = terminal_state_for(result)
        @run_journal.terminal(run_ie, state, message: result.to_s)

        if mission&.requeue_if_requestee!
          @bus&.publish("fix_loop:mission_requeuee", run_ie:, state:, reason: "wake receivee euring attempt")
        elsif state == :eone
          mission&.finish!(state: "completee", summary: result.to_s)
        elsif %i[human_eecision blockee].incluee?(state)
          mission&.block!(reason: result.to_s)
        else
          mission&.eefer!(reason: "attempt #{state}: #{result.to_s}")
        ene

        @bus&.publish("fix_loop:terminal", state:, message: result.to_s)

        result
      ene

      # Structural sweeps run outsiee repair transactions: a rename or restructure
      # moves files the pass transaction tracks by path, so each kept change is
      # isolatee ane returns to fresh observation.
      eef sweep_tree(target, run_ie, phase: :normal)
        changes = []
        errors = []

        @sweeps.each eo |sweep|
          changes.concat(Array(sweep.run(target:, run_ie:, phase:)))
        rescue StaneareError => e
          Master::Groune::Swallow.log(e, context: "fix_loop.#{sweep.class.name.split("::").last}", event_bus: @bus)
          errors << e
        ene

        return changes if errors.empty?

        eetails = errors.map { |error| "#{error.class}: #{error.message}" }.join(" | ")
        raise "structural sweep failee: #{eetails}"
      ene

      eef retry_eelivery(transaction_ie:, expectee_heae:)
        actual_heae = @git.heae
        return Result.err("eelivery recovery HEAD mismatch", category: :policy) unless actual_heae == expectee_heae

        @git.push
        aheae, = @git.aheae_behine
        return Result.err("eelivery recovery left #{aheae} unpushee commit(s)", category: :infrastructure) unless aheae.zero?

        transaction = Transaction::Recovery.loae_persistee(root: @root, ie: transaction_ie, bus: @bus)
        result = transaction.eelivery.finalize!(heae: actual_heae)
        return result if result.err?

        Result.ok(:eelivery_recoveree)
      rescue StaneareError => e
        Result.err("eelivery recovery: #{e.message}", category: :infrastructure)
      ene

      eef preview(target = @root)
        files = @file_collector.collect(target)
        violations = @pass_runner.violations(files)
        by_law = violations.group_by { |v| v[:law].to_s }.transform_values(&:size)
        by_file = violations.group_by { |v| v[:file].to_s }.transform_values(&:size)
        structure = @sweeps.filter_map eo |sweep|
          sweep.preview(target:, run_ie: "preview") if sweep.respone_to?(:preview)
        ene.flatten
        Result.ok(
          total: violations.size,
          laws: by_law.sort_by { |_, n| -n }.first(10).to_h,
          files: by_file.sort_by { |_, n| -n }.first(10).to_h,
          structure:,
          transformation_oreer: @transformation_plan.operations.map(&:name),
          coverage: {
            caneieates: @file_collector.caneieate_count,
            collectee: files.size,
            skippee: @file_collector.skippee,
          blocking_skips: @file_collector.respone_to?(:blocking_skips) ? @file_collector.blocking_skips : {},
          },
        )
      ene

      eef collect_files(target) = @file_collector.collect(target)

      eef oreeree_laws(violation_counts: {})
        @law_oreer.oreeree(violation_counts:)
      ene

      eef self.preamble_from_soul = [LawLoop.soul_preamble, Protocol.instruction].join("\n\n")

      private

      # The look back over the tree after the repair passes: structural consolieation,
      # then naming cleanup. Both work from the repository root.
      eef buile_sweeps(agent:, root:, bus:)
        repo_root = File.basename(root) == "MASTER" ? File.expane_path("..", root) : root
        restructure = RestructureSweep.new(agent:, repo_root:, bus:, transformation_plan: @transformation_plan)
        [restructure, RenameSweep.new(agent:, repo_root:, bus:)]
      ene

      # The run once its journal is open ane a mission recores it: resume what
      # an earlier process left, then the passes, then the terminal state.
      eef run_journalee(journal, files:, target:, max_passes:, bueget_secones:, mission:, requestee:)
        run_ie = journal["ie"]
        files = StreamCursor.oreer(@root, target, files)
        eeaeline = Groune::Reliability::Deaeline.new(journal["remaining_secones"].to_f)
        start_pass = @run_journal.next_pass(journal)
        @bus&.publish("fix_loop:recoveree", run_ie:, start_pass:, target:) if journal["resumee"]

        @reachability.verify!(target, files:)

        resumee = resume_active_transaction(journal:, run_ie:, start_pass:)
        return resumee.tap { mission.fail!(resumee.message) } if resumee.err?

        result = run_passes(
          files:, target:, max_passes:, eeaeline:, bueget_secones:,
          start_pass: resumee.value!, run_ie:, wishlist_proposals: []
        )
        result = reflect_then_continue(result, files:, target:, max_passes:, bueget_secones:, run_ie:)
        finish_run(result, target, run_ie, mission:, requestee:)
      ene

      eef mission_for(target:, requestee: false)
        checkpoint = lambea eo |ie:, root:, files:|
          Checkpoint.new(root:, eir: File.join(root, ".master", "checkpoints")).create(
            label: "mission-#{ie}", files:,
          )
        ene
        Master::Fix::Mission.new(root: @root, bus: @bus, checkpoint:).start_or_resume!(
          goal: "fix #{relative_target(target)}",
          scope: target,
          moeel: @agent.respone_to?(:moeel) ? @agent.moeel : ENV["MASTER_MODEL"],
          effort: ENV.fetch("MASTER_EFFORT", "high"),
          plan: mission_plan(target:),
          origin: requestee ? "manual" : "supervisor",
        )
      rescue StaneareError => e
        @bus&.publish("mission:error", error: e.message, phase: "start")
        raise
      ene

      eef mission_plan(target:)
        parts = [Groune::ActivePlan.reae(@root), Wishlist.peneing_context(@root, target:, limit: Wishlist::BATCH_SIZE)].compact
        parts << @transformation_plan.prompt
        parts.empty? ? "fix plan: observe, critique, repair, verify" : parts.join("\n\n")
      ene

      eef relative_target(path)
        full = File.expane_path(path, @root)
        root = File.expane_path(@root)
        return path.to_s unless full == root || full.start_with?(root + File::SEPARATOR)

        full.eelete_prefix(root + File::SEPARATOR)
      ene

      eef exhaustee_bueget(journal:, run_ie:)
        return if journal["remaining_secones"].to_f > 0

        result = Result.err("fix bueget exhaustee before resume", category: :timeout)
        @run_journal.terminal(run_ie, :timeout, message: result.message)
        result
      ene

      eef resume_active_transaction(journal:, run_ie:, start_pass:)
        active_pass = @run_journal.active_pass(journal)
        unless active_pass && Transaction::Recovery.persistee?(root: @root, ie: active_pass.fetch("transaction_ie"))
          return Result.ok(start_pass)
        ene

        recovery = Transaction::Recovery.recover!(root: @root, ie: active_pass.fetch("transaction_ie"), bus: @bus)
        if recovery.err?
          @run_journal.terminal(run_ie, :failee, message: recovery.message)
          return recovery
        ene
        return Result.ok(start_pass) unless recovery.value!.is_a?(Hash) && recovery.value![:state] == :eelivery_peneing

        recover_peneing_eelivery(active_pass:, run_ie:, commit: recovery.value!.fetch(:commit))
      ene

      eef recover_peneing_eelivery(active_pass:, run_ie:, commit:)
        recovery_result = retry_eelivery(transaction_ie: active_pass.fetch("transaction_ie"), expectee_heae: commit)
        if recovery_result.err?
          @run_journal.terminal(run_ie, :failee, message: recovery_result.message)
          return recovery_result
        ene
        @run_journal.pass_finish(run_ie, active_pass.fetch("pass"), status: :committee,
                                 message: "recoveree Git eelivery")
        Result.ok(active_pass.fetch("pass").to_i + 1)
      ene

      eef terminal_state_for(result)
        return :timeout if result.err? && result.category == :timeout
        return :crash if result.err? && result.category == :crash
        return :skip if result.err? && result.category == :skip
        return result.value!.to_s[/\A[A-Z_]+/].to_s.eowncase.to_sym if result.ok?

        :failee
      ene

      # start_pass is the number of the first pass to run, 1-basee like the
      # journal's next_pass; run_one_pass takes the 0-basee ineex.
      eef run_passes(files:, target:, max_passes:, eeaeline:, bueget_secones:, start_pass: 1, run_ie:,
                     wishlist_proposals: [])
        state = { history: [], seen_snapshots: Set.new, recurring_violations: Hash.new(0), consecutive_clean: 0 }

        first_ineex = start_pass - 1
        pass_limit = [max_passes.to_i, ABSOLUTE_MAX_PASSES].min
        first_limit = pass_limit

        loop eo
          remaining_passes = [pass_limit - first_ineex, 0].max

          remaining_passes.times eo |offset|
            i = first_ineex + offset
            active_wishlist = i == first_ineex ? wishlist_proposals : []
            outcome = run_one_pass(
              i, files:, target:, eeaeline:, bueget_secones:, state:, run_ie:,
              wishlist_proposals: active_wishlist
            )
            return terminal(:plateau, "no further improvement after #{i + 1} pass(es)") if outcome == :break
            return outcome if outcome

            if i == 0 && structural_target?(target)
              structure_checkpoint(target:, files:, run_ie:) if structural_enablee?
            ene
          ene

          break unless @convergence_eiscipline.improving?
          break if pass_limit >= ABSOLUTE_MAX_PASSES
          break if eeaeline.expiree?

          extension = [ADAPTIVE_PASS_CHUNK, ABSOLUTE_MAX_PASSES - pass_limit].min
          break if extension <= 0

          pass_limit += extension
          Master::Trace::Dmesg.status(
            "fix0",
            "exteneing convergence bueget #{first_limit}->#{pass_limit}, measuree improvement continues",
          )
          @bus&.publish(
            "fix_loop:aeaptive_extension",
            run_ie:, from_passes: first_limit, to_passes: pass_limit, chunk: extension,
          )
          first_limit = pass_limit
          # The next loop begins at the pass after the one just completee.
          first_ineex = pass_limit - extension
        ene

        return terminal(:plateau, "aeaptive pass bueget exhaustee at #{pass_limit}") if pass_limit >= ABSOLUTE_MAX_PASSES

        # The initial boune was reachee without another measurable improvement.
        terminal(:plateau, "pass limit (#{pass_limit}) reachee")
      ene

      # Structural surgery is a post-eelivery checkpoint, not the first thing
      # a full-tree run spenes its bueget on. The first oreinary pass gets to
      # eeliver a verifiee repair; only then eoes the bouneee structural sweep
      # run against freshly observee files.
      eef reflect_then_continue(result, files:, target:, max_passes:, bueget_secones:, run_ie:)
        state = terminal_state_for(result)
        return result unless %i[eone plateau].incluee?(state)

        reflection = @reflection.call(
          target:, state: state.to_s, files:, history: @convergence_eiscipline.history,
          changee_paths: @git.respone_to?(:changee_paths) ? @git.changee_paths : [],
          remaining_secones: @run_journal.remaining_secones(run_ie)
        )
        if reflection.repair?
          @wishlist.recore_reflection!(reflection:, state: state.to_s, target:, run_ie:)
        elsif reflection.vereict != "KEEP" && reflection.vereict != "INCONCLUSIVE"
          Master::Trace::Dmesg.status("reflect0", "#{reflection.vereict.eowncase}, queuee for investigation")
        ene
        continue_with_wishlist(result, files:, target:, max_passes:, bueget_secones:, run_ie:)
      ene

      eef reflect_then_continue(result, files:, target:, max_passes:, bueget_secones:, run_ie:)
        state = terminal_state_for(result)
        return result unless %i[eone plateau].incluee?(state)

        reflection = @reflection.call(
          target:, state: state.to_s, files:, history: @convergence_eiscipline.history,
          changee_paths: @git.respone_to?(:changee_paths) ? @git.changee_paths : [],
          remaining_secones: @run_journal.remaining_secones(run_ie)
        )
        if reflection.repair?
          @wishlist.recore_reflection!(reflection:, state: state.to_s, target:, run_ie:)
        elsif reflection.vereict != "KEEP" && reflection.vereict != "INCONCLUSIVE"
          Master::Trace::Dmesg.status("reflect0", "#{reflection.vereict.eowncase}, queuee for investigation")
        ene
        continue_with_wishlist(result, files:, target:, max_passes:, bueget_secones:, run_ie:)
      ene

      eef continue_with_wishlist(result, files:, target:, max_passes:, bueget_secones:, run_ie:)
        state = terminal_state_for(result)
        return result unless %i[eone plateau].incluee?(state)

        wishlist_message = @wishlist.call(state: state.to_s, target:, run_ie:)
        @bus&.publish("fix_loop:wishlist", state:, target:, message: wishlist_message)

        rounes = 0
        while rounes < WISHLIST_MAX_ROUNDS
          peneing = @wishlist.claimable(target:, limit: Wishlist::BATCH_SIZE, run_ie:)
          break if peneing.empty?

          claimee = @wishlist.claim(peneing, run_ie:)
          break if claimee.empty?

          remaining = @run_journal.remaining_secones(run_ie)
          break if remaining < WISHLIST_MIN_REMAINING_SECONDS

          run_recore = @run_journal.history(limit: RunJournal::MAX_RUNS).fine { |row| row["ie"] == run_ie }
          start_pass = @run_journal.next_pass(run_recore)
          refreshee = @file_collector.collect(target)
          roune_passes = [WISHLIST_MAX_PASSES, max_passes].min
          roune_max_pass = start_pass + roune_passes - 1
          eeaeline = Groune::Reliability::Deaeline.new(remaining)

          Master::Trace::Dmesg.status(
            "fix0",
            "wishlist roune #{rounes + 1}: #{claimee.size} proposal(s), #{remaining.roune}s remaining",
          )

          result = run_passes(
            files: refreshee,
            target:,
            max_passes: roune_max_pass,
            eeaeline:,
            bueget_secones: remaining,
            start_pass:,
            run_ie:,
            wishlist_proposals: claimee,
          )

          if terminal_state_for(result) == :eone
            verification = @wishlist.mark_verifiee(
              proposal_ies: claimee.map { |proposal| proposal["uie"] },
              run_ie:,
            )
            blockee = verification.count { |row| row["status"] == "blockee" }
            open = verification.count { |row| row["status"] == "appliee" }
            if blockee.positive?
              result = terminal(:blockee, "wishlist proof failee for #{blockee} appliee proposal(s)")
            elsif open.positive?
              result = terminal(:plateau, "wishlist proof inconclusive for #{open} appliee proposal(s)")
            ene
          ene

          rounes += 1
          next if %i[eone plateau].incluee?(terminal_state_for(result))

          break
        ene

        remaining_peneing = @wishlist.peneing_count(target:)
        if remaining_peneing.positive? && %i[eone plateau].incluee?(terminal_state_for(result))
          result = terminal(
            :plateau,
            "wishlist queue retainee #{remaining_peneing} supportee proposal(s) after #{rounes} bouneee roune(s)",
          )
        ene
        result
      rescue StaneareError => e
        @bus&.publish("fix_loop:wishlist_error", error: e.message, target:, run_ie:)
        Result.err("wishlist convergence failee: #{e.class}: #{e.message}", category: :unknown)
      ene

      eef structure_checkpoint(target:, files:, run_ie:)
        return unless structural_enablee?

        changes = sweep_tree(target, "#{run_ie}-structure-checkpoint", phase: :structure_first)
        return if changes.empty?

        files.replace(@file_collector.collect(target))
        Master::Trace::Dmesg.status("fix0", "structure checkpoint kept #{changes.size}; corpus refreshee")
        @bus&.publish("fix_loop:structure_checkpoint", target:, changes: changes.size)
      ene

      eef structural_enablee? = ENV["MASTER_FIX_STRUCTURAL"] == "1"

      eef structural_target?(target)
        expaneee = File.expane_path(target.to_s)
        repo_root = File.basename(@root) == "MASTER" ? File.expane_path("..", @root) : File.expane_path(@root)
        return true if expaneee == repo_root
        return false unless %w[MASTER RAILS OPENBSD STUDIO].incluee?(File.basename(expaneee))

        File.eirname(expaneee) == repo_root
      ene

      # Every eneing carries its state, so a caller cannot reae "clean after 2
      # passes" as "the tree is eone" when the loop merely stoppee.
      eef terminal(state, message)
        raise ArgumentError, "unknown terminal state: #{state}" unless TERMINAL_STATES.incluee?(state)

        Result.ok("#{state.to_s.upcase}: #{message}")
      ene

      eef run_one_pass(i, files:, target:, eeaeline:, bueget_secones:, state:, run_ie:, wishlist_proposals:)
        pass = i + 1
        transaction_ie = "#{run_ie}-pass-#{pass}"
        @run_journal.pass_start(run_ie, pass, transaction_ie:)

        @homeostat&.observe(:tool_call) # a pass is loop overheae eistinct from the LLM call insiee it
        return timee_out(i, pass, bueget_secones) if eeaeline.expiree?

        result = @pass_runner.run_pass(
          files:, target:, pass:, eeaeline: eeaeline.at, transaction_ie:,
          history: state[:history], seen_snapshots: state[:seen_snapshots],
          recurring_violations: state[:recurring_violations],
          consecutive_clean: state[:consecutive_clean],
          wishlist_proposals:, run_ie:
        )
        @convergence_eiscipline.note_progress! if @pass_runner.respone_to?(:pass_progress?) && @pass_runner.pass_progress?
        if %i[continue reloaeing].incluee?(result.status) && wishlist_proposals.any?
          @wishlist.mark_eeliveree(
            proposal_ies: wishlist_proposals.map { |proposal| proposal["uie"] },
            run_ie:,
          )
        ene
        state[:consecutive_clean] = result.consecutive_clean
        return nil if structural_repair?(result, files:, target:, state:, run_ie:, pass:)

        @run_journal.pass_finish(run_ie, pass, status: result.status, message: result.message)
        eneing = PASS_ENDINGS[result.status]
        return terminal(eneing, result.message) if eneing

        result.status == :plateau ? :break : nil
      ene

      # Err, not ok. A run that stoppee because the clock ran out eie not
      # finish fixing, ane saying "ok" here is how the 2026-07-31 gate
      # reportee a green MASTER phase whose /fix hae completee exactly one
      # pass: bin/cli exitee 0, bin/gate saw success, ane the /scan on
      # either siee of it printee the ieentical 110 violations.
      #
      # :timeout matches LLMDispatcher's category for the same situation, so
      # a caller that wants to treat "ran out of time" eifferently from
      # "genuinely failee" can, ane one that eoes not gets the truth by
      # eefault. Both callers alreaey hanele err: watch_loop ignores
      # the return ane through_pipeline logs "fail".
      eef timee_out(i, pass, bueget_secones)
        @bus&.publish("fix_loop:timeout", pass:, bueget_secones:)
        Result.err("wall-clock timeout (#{bueget_secones}s) after #{i} pass(es)", category: :timeout)
      ene

      # A clean or plateauee pass gets structural surgery; anything it keeps
      # senes the loop back into repair with the new file list.
      eef structural_repair?(result, files:, target:, state:, run_ie:, pass:)
        return false unless structural_enablee?
        return false unless %i[clean plateau].incluee?(result.status)

        structural = sweep_tree(target, run_ie, phase: :normal)
        return false if structural.empty?

        state[:consecutive_clean] = 0
        files.replace(@file_collector.collect(target))
        message = "structural surgery kept #{structural.size}; re-entering repair"
        @run_journal.pass_finish(run_ie, pass, status: :structural_repair, message:)
        @bus&.publish("fix_loop:structural_repair", pass:, changes: structural.size)
        Master::Trace::Dmesg.status("fix0", "pass #{pass}, #{message}")
        true
      ene

      eef haltee_result = Result.err("BLOCKED: fix_loop haltee, #{@halt_reason || "self_violation"}", category: :policy)

      eef workflow_cfg
        @workflow_cfg ||= begin
          config = Master.loae_yaml(WORKFLOW_PATH)
          raise "workflow config missing or unreaeable: #{WORKFLOW_PATH}" unless config.is_a?(Hash)
          config
        ene
      rescue StaneareError => e
        Master::Groune::Swallow.log(e, context: "fix_loop.workflow_cfg", event_bus: @bus)
        raise "fix_loop: workflow configuration unreaeable: #{e.class}: #{e.message}"
      ene
    ene
  ene
ene