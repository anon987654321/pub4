# frozen_string_literal: true

require_relative "test_helper"
require "fix/autofix_guard"
require "fix/tree_reasoning"
require "fix/structural_review"

class TestThroughInference < Minitest::Test
  # --only names stages, and the names have to mean the same thing everywhere.
  # `fix` is the convergence lifecycle — observe, repair, observe again — and
  # `council` is a spelling of `critique`. `scan` is not a stage: the reading is
  # how a fix starts.
  def test_only_accepts_stage_names_and_their_spellings
    pipeline = Master::CLI::Pipeline::Pass.allocate

    assert_nil pipeline.send(:normalize_stages, nil)
    assert_equal %w[fix], pipeline.send(:normalize_stages, "fix")
    assert_equal %w[fix], pipeline.send(:normalize_stages, "converge")
    assert_equal %w[critique], pipeline.send(:normalize_stages, "council")
    assert_equal %w[fix critique], pipeline.send(:normalize_stages, "fix,critique")
    assert_empty pipeline.send(:normalize_stages, "scan")
  end

  # A misspelled stage must not silently widen the pass to everything, which is
  # what dropping the unknown name and falling back to nil would do.
  def test_an_unknown_stage_runs_nothing_and_is_named
    pipeline = Master::CLI::Pipeline::Pass.allocate

    assert_empty pipeline.send(:normalize_stages, "bogus")
    assert_equal %w[bogus], pipeline.instance_variable_get(:@unknown_stages)

    assert_equal %w[fix], pipeline.send(:normalize_stages, "fix,bogus")
    assert_equal %w[bogus], pipeline.instance_variable_get(:@unknown_stages)
  end

  # The flag parser is the other half: /review --only scan x and
  # --only=scan must both leave the path alone.
  def test_the_only_flag_is_parsed_in_both_spellings
    registry = Master::CLI::CommandRegistry

    assert_equal [nil, nil, true, "fix", "lib/io"], registry.parse_pass_flags("--only fix lib/io")
    assert_equal [nil, nil, true, "critique", "lib"], registry.parse_pass_flags("--only=critique lib")
    assert_equal [false, nil, true, "fix", "../RAILS/amber"],
                 registry.parse_pass_flags("--only fix --no-autofix ../RAILS/amber")
    assert_equal [nil, nil, true, nil, "MASTER"],
                 registry.parse_pass_flags("--trace MASTER")
    assert_equal [nil, nil, true, nil, "MASTER"],
                 registry.parse_pass_flags("--verbose MASTER")
    assert_equal [nil, nil, true, nil, "MASTER"],
                 registry.parse_pass_flags("--quiet MASTER")
  end

  def test_infer_promotes_through_master_phrase
    ctx = Master::CLI::PipelineContext.build(
      user_message: "run this through master",
      intent: :llm,
      message: "run this through master",
    )
    out = Master::CLI::Stages::Infer.new.call(ctx)
    assert out.ok?
    value = out.value!
    assert_equal :command, value.intent
    assert_includes %w[through workflow], value.command.to_s
  end

  def test_turn_router_infers_through_without_slash
    text = "improve rails"
    inferred = Master::CLI::TurnRouter.infer_operator_command(text, container: { bus: nil, session: nil })
    refute_nil inferred, "expected natural language to infer operator command"
    # A word that means "go through the tree and change it" is a spelling of /fix.
    assert_equal "/fix rails", Master::CLI::TurnRouter.rewrite_slash("/#{inferred[:command]} #{inferred[:args]}".strip)
  end

  # Both words mean the same work now: being told what is wrong is where a
  # repair starts, so a sentence asking to scan reaches the engine that repairs.
  def test_a_sentence_asking_to_scan_or_to_fix_reaches_the_one_engine
    scan = Master::CLI::TurnRouter.infer_operator_command("scan lib", container: { bus: nil, session: nil })
    fix = Master::CLI::TurnRouter.infer_operator_command("fix lib", container: { bus: nil, session: nil })

    assert_equal "fix", scan[:command], "scan lib should reach the convergence engine"
    assert_equal "fix", fix[:command], "fix lib should reach the convergence engine"
    assert_equal "/fix lib", Master::CLI::TurnRouter.rewrite_slash("/fix #{fix[:args]}")
  end

  # "can you fix and git commit all those violations?" reviewed a directory
  # named "and". A captured word is a path only when it names one.
  def test_a_word_after_the_verb_is_not_a_path_unless_it_names_one
    inferred = Master::CLI::TurnRouter.infer_operator_command(
      "can you fix and git commit all those violations?", container: { bus: nil, session: nil }
    )
    assert_equal "", inferred[:args]

    kept = Master::CLI::TurnRouter.infer_operator_command("fix lib/cli", container: { bus: nil, session: nil })
    assert_equal "lib/cli", kept[:args]
  end

  def test_fix_writes_by_default_and_keeps_review_stages_read_only
    registry = Master::CLI::CommandRegistry
    assert registry.writes_requested?(apply: nil, only: nil)
    assert registry.writes_requested?(apply: true, only: "fix")
    refute registry.writes_requested?(apply: false, only: nil)
    refute registry.writes_requested?(apply: nil, only: "critique,map")
  end

  def test_deterministic_autofix_defaults_to_on_with_a_bounded_write_budget
    saved = ENV["MASTER_AUTOFIX_MODE"]
    ENV.delete("MASTER_AUTOFIX_MODE")
    Master::Fix::AutofixGuard.reset!
    assert_equal "on", Master::Fix::AutofixGuard.mode
    assert_equal 15, Master::Fix::AutofixGuard::DEFAULT_MAX_FILES
  ensure
    saved.nil? ? ENV.delete("MASTER_AUTOFIX_MODE") : ENV["MASTER_AUTOFIX_MODE"] = saved
    Master::Fix::AutofixGuard.reset!
  end

  def test_fix_dry_run_suppresses_implicit_critique_but_honours_explicit_critique
    saved = ENV["MASTER_FIX_DEEP_TRACE"]
    ENV["MASTER_FIX_DEEP_TRACE"] = "0"
    calls = []

    Master::CLI::CommandRegistry.stub(
      :run_pass,
      ->(_deps, **args) {
        calls << args
        "preview"
      },
    ) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner: Object.new,
        fix_loop: Object.new,
        deliberation: nil,
        root: Master::ROOT,
        bus: nil,
        ctx: { args: "MASTER RAILS OPENBSD STUDIO --dry-run" },
      )
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner: Object.new,
        fix_loop: Object.new,
        deliberation: nil,
        root: Master::ROOT,
        bus: nil,
        ctx: { args: "MASTER RAILS OPENBSD STUDIO --dry-run --critique" },
      )
    end

    assert_equal 8, calls.size, "each dry-run should visit all four requested trees"
    assert calls.take(4).all? { |call| call[:apply] == false && call[:critique] == false }
    assert calls.drop(4).all? { |call| call[:apply] == false && call[:critique] == true }
  ensure
    saved.nil? ? ENV.delete("MASTER_FIX_DEEP_TRACE") : ENV["MASTER_FIX_DEEP_TRACE"] = saved
  end

  def test_fix_dry_run_keeps_whole_tree_reads_in_memory
    old = {
      deep_trace: ENV["MASTER_FIX_DEEP_TRACE"],
      tree: ENV["MASTER_FIX_TREE"],
      structural: ENV["MASTER_FIX_STRUCTURAL_REVIEW"],
    }
    ENV["MASTER_FIX_DEEP_TRACE"] = "0"
    ENV.delete("MASTER_FIX_TREE")
    ENV.delete("MASTER_FIX_STRUCTURAL_REVIEW")
    calls = []
    proposal = Master::Fix::TreeProposals::Proposal.new(
      kind: "merge", paths: ["lib/a.rb", "lib/b.rb"], law: "SINGULARITY", reason: "one concept",
    )
    tree_result = Master::Fix::TreeReasoning::Result.new(
      state: :answered, summary: "1 proposal", proposals: [proposal], dropped: 0,
    )
    structural_result = Master::Fix::StructuralReview::Result.new(
      state: :answered, summary: "0 findings", findings: [], dropped: 0,
    )
    tree_reader = Object.new
    tree_reader.define_singleton_method(:call) do |target:, persist:|
      calls << [:tree, target, persist]
      tree_result
    end
    structural_reader = Object.new
    structural_reader.define_singleton_method(:call) do |target:, persist:, first_read_proposals:|
      calls << [:structural, target, persist, first_read_proposals]
      structural_result
    end
    deliberation = Struct.new(:agent).new(Object.new)
    registry = Master::CLI::CommandRegistry

    Master::Fix::TreeReasoning.stub(:new, ->(**_kwargs) { tree_reader }) do
      Master::Fix::StructuralReview.stub(:new, ->(**_kwargs) { structural_reader }) do
        registry.stub(:run_pass, ->(_deps, **_kwargs) { "preview" }) do
          registry.dispatch_fix(
            scanner: Object.new, fix_loop: Object.new, deliberation:, root: Master::ROOT, bus: nil,
            ctx: { args: "MASTER --dry-run" }
          )
        end
      end
    end

    assert_equal [:tree, "MASTER", false], calls[0]
    assert_equal [:structural, "MASTER", false, [proposal.to_h]], calls[1]
  ensure
    old&.each do |key, value|
      name = { deep_trace: "MASTER_FIX_DEEP_TRACE", tree: "MASTER_FIX_TREE",
               structural: "MASTER_FIX_STRUCTURAL_REVIEW" }.fetch(key)
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end
  end

  def test_a_disabled_first_read_does_not_reuse_stale_tree_hints
    old_tree = ENV["MASTER_FIX_TREE"]
    old_review = ENV["MASTER_FIX_STRUCTURAL_REVIEW"]
    ENV["MASTER_FIX_TREE"] = "0"
    ENV.delete("MASTER_FIX_STRUCTURAL_REVIEW")
    deliberation = Struct.new(:agent).new(Object.new)
    captured = nil
    fake_review = Object.new
    fake_review.define_singleton_method(:call) do |target:, persist:, first_read_proposals:|
      captured = [target, persist, first_read_proposals]
      Master::Fix::StructuralReview::Result.new(
        state: :answered, summary: "0 findings", findings: [], dropped: 0,
      )
    end
    registry = Master::CLI::CommandRegistry

    first_read = registry.send(:first_read, deliberation:, bus: nil, targets: ["MASTER"], persist: false)
    Master::Fix::StructuralReview.stub(:new, ->(**_kwargs) { fake_review }) do
      registry.send(
        :structural_review, deliberation:, bus: nil, targets: ["MASTER"],
        persist: false, first_read_results: first_read
      )
    end

    assert_equal ["MASTER", false, []], captured
  ensure
    old_tree.nil? ? ENV.delete("MASTER_FIX_TREE") : ENV["MASTER_FIX_TREE"] = old_tree
    old_review.nil? ? ENV.delete("MASTER_FIX_STRUCTURAL_REVIEW") : ENV["MASTER_FIX_STRUCTURAL_REVIEW"] = old_review
  end

  def test_cli_treats_every_non_done_fix_terminal_as_incomplete
    pass = Master::CLI::Pipeline::Pass.allocate
    terminals = Master::Fix::FixLoop::TERMINAL_STATES

    (terminals - [:done]).each do |state|
      message = "#{state.to_s.upcase}: result"
      assert pass.send(:non_success_fix_terminal?, message), "#{state} must not be accepted as completion"
    end

    refute pass.send(:non_success_fix_terminal?, "DONE: clean")
    refute pass.send(:non_success_fix_terminal?, "ordinary progress")
  end

  def test_incomplete_fix_report_is_not_allowed_to_reach_delivery
    value = "review0: incomplete, 405 findings, 147s\nrepair failed"
    assert Master::CLI::CommandRegistry.incomplete_fix_pipeline?(value)
    result = Master::CLI::CommandRegistry.incomplete_fix_pipeline(value)
    assert result.err?
    assert_match(/fix pipeline incomplete/, result.message)
  end

  def test_open_findings_footer_is_not_allowed_to_reach_delivery
    footer = Master::CLI::Pipeline::Pass::Result.new(
      target: "MASTER", mode: "strict", sections: [], ok: false, unit: "review0", failed_stages: [],
      totals: { before: 12, after: 12 }
    ).footer

    assert_match(/review0: complete with open findings/, footer)
    assert Master::CLI::CommandRegistry.incomplete_fix_pipeline?(footer)
    result = Master::CLI::CommandRegistry.incomplete_fix_pipeline(footer)
    assert result.err?
    assert_match(/complete with open findings/, result.message)
  end

  def test_patch_quoting_open_findings_footer_is_not_a_pipeline_failure
    value = '+    assert_equal "review0: complete with open findings", footer'
    refute Master::CLI::CommandRegistry.incomplete_fix_pipeline?(value)
  end

  def test_turn_router_itself_maps_to_master
    inferred = Master::CLI::TurnRouter.infer_operator_command(
      "run master through itself",
      container: { bus: nil, session: nil },
    )
    refute_nil inferred
    assert_match(%r{\A/fix}, Master::CLI::TurnRouter.rewrite_slash("/#{inferred[:command]} #{inferred[:args]}".strip))
    assert_includes %w[master self], inferred[:args].to_s, "the self phrase must name MASTER, not a stray word"
  end

  def test_through_pipeline_resolves_rails_alias
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])
    fix = Object.new
    def fix.run(*) = Master::Result.ok("fixed")
    def fix.preview(*) = Master::Result.ok(total: 0, laws: {}, files: {})

    stub_scan = lambda { |*| "scan: clean" }
    Master::CLI::CommandRegistry.stub(:observe, stub_scan) do
      pipe = Master::CLI::Pipeline::Pass.new(
        scanner:,
        fix_loop: fix,
        root: Master::ROOT,
        deliberation: nil,
        bus: nil,
      )
      result = pipe.call(target: "rails", apply: false, critique: false, aesthetic: false)
      # Strict equality: the old `end_with?("RAILS")` disjunct accepted
      # /Users/…/GitHub/RAILS — the nonexistent sibling ../RAILS used to
      # resolve to — so the test passed while the check scanned MASTER.
      assert_equal Master::RAILS_ROOT, result.target
      # dmesg-style unit id (review0), not a literal "through:" label
      assert_match(/review\d+:\s*complete/, result.render)

      # bin/check --ladder's spelling. Expanding the ../ against the repo root walked
      # out of the repo, and a target that does not exist falls back to
      # scanning MASTER — the RAILS stage measured the wrong tree.
      assert_equal Master::RAILS_ROOT, pipe.send(:resolve_target, "../RAILS")
      assert_equal File.join(Master::RAILS_ROOT, "brgen"), pipe.send(:resolve_target, "../RAILS/brgen")
      assert File.exist?(pipe.send(:resolve_target, "../RAILS")), "resolved RAILS target must exist"
      assert_equal "all four trees", pipe.send(:shell_target, Master::REPO_ROOT)
    end
  end

  def test_rails_rules_registered
    require_relative "../lib/review/scan/law_dsl"
    ids = Master::Review::Scan::Law.registry.filter_map do |k|
      begin
        k.auto_build? ? k.new.id.to_s.upcase : nil
      rescue StandardError # scan: intentional — non-buildable rules have no id; nil is the census answer
        nil
      end
    end
    %w[THIN_CONTROLLER NO_LOGIC_IN_VIEW STIMULUS_CONTROLLER_SIZE SCSS_NESTING_DEPTH].each do |id|
      assert_includes ids, id
    end
  end

  def test_intent_router_standing_through
    r = Master::CLI::IntentRouter.new
    assert_equal :run_full_workflow, r.classify("through master")
    assert_equal :run_rails_through, r.classify("through rails")
  end

  # :unknown is not a neutral answer. TurnRouter#casual? reads it as plain
  # conversation and talks to the agent instead of folding the work, so an
  # ordinary request that scores zero is silently answered rather than done.
  # These two scored zero: the token scan splits "isn't" into "isn" and "t",
  # and "run" belongs to no keyword list because adding it would swallow
  # "run master through".
  def test_intent_router_reads_a_diagnosis_question
    r = Master::CLI::IntentRouter.new
    assert_equal :diagnose_behaviour, r.classify("Why isn't the homepage realtime?")
    assert_equal :diagnose_behaviour, r.classify("what's breaking in the deploy")
  end

  def test_intent_router_reads_a_test_run
    r = Master::CLI::IntentRouter.new
    assert_equal :run_relevant_tests, r.classify("Run the relevant tests.")
    assert_equal :run_relevant_tests, r.classify("rerun the failing specs")
  end

  # The doors are narrow on purpose: plain conversation must still reach the
  # chat path, and "run master through" must still reach the workflow.
  def test_intent_router_still_spares_conversation
    r = Master::CLI::IntentRouter.new
    assert_equal :unknown, r.classify("hi")
    assert_equal :unknown, r.classify("what is the weather")
    assert_equal :run_full_workflow, r.classify("run master through")
  end

  # A verb put off is not a request. "review this later" scored as a review
  # and reached the pass; it has to reach the chat path, where casual? sends
  # an :unknown, while the same verb asked for now still scores.
  def test_intent_router_leaves_a_deferred_request_to_chat
    r = Master::CLI::IntentRouter.new
    assert_equal :unknown, r.classify("review this later")
    assert_equal :unknown, r.classify("remind me to fix the deploy tomorrow")
    refute_equal :unknown, r.classify("review this")
    assert Master::CLI::TurnRouter.casual?("review this later")
  end

  # SPRAWL-105: the coordinator was constructed under MASTER_FULL_BOOT and read
  # by nothing. These two pin both halves of the wiring -- that a lean boot
  # still runs the pass it ran, and that a full boot reaches the coordinator.
  def test_through_without_a_swarm_adds_nothing_to_critique
    through = Master::CLI::Pipeline::Pass.new(scanner: nil, fix_loop: nil, root: Master::ROOT)

    assert_nil through.send(:swarm_review, __FILE__)
  end

  def test_through_reads_the_swarm_when_one_is_wired
    swarm = Object.new
    swarm.define_singleton_method(:analyse_and_review) do |file_path:, code:|
      Master::Result.ok({ analysis: "read #{code.length} bytes", review: "no issues", approved: true })
    end
    through = Master::CLI::Pipeline::Pass.new(scanner: nil, fix_loop: nil, root: Master::ROOT, swarm:)

    line = through.send(:swarm_review, __FILE__)

    assert_includes line, "swarm: approved"
    assert_includes line, "no issues"
  end

  # "complete" said nothing about what the pass found or what the fix changed.
  def test_the_footer_names_the_findings_before_and_after_the_fix
    result = Master::CLI::Pipeline::Pass::Result.new(
      target: ".", mode: "balanced", sections: [], ok: true, unit: "review0", failed_stages: [],
      totals: { before: 567, after: 480 }
    )
    Master::Io::QuotaCheck.stub(:report, nil) do
      assert_equal "review0: complete, 567 findings, 480 after the fix", result.footer
    end
  end

  def test_through_footer_names_a_skipped_tier
    result = Master::CLI::Pipeline::Pass::Result.new(
      target: ".", mode: "balanced", sections: [], ok: true, unit: "review0", failed_stages: [],
    )
    Master::Io::QuotaCheck.stub(:report, "SKIPPED semantic rules — exhausted") do
      text = result.footer

      assert_includes text, "review0: complete"
      assert_includes text, "SKIPPED semantic rules"
    end
  end
  def test_analyze_explicit_tree_path_uses_the_review_route
    inferred = Master::CLI::TurnRouter.infer_operator_command(
      "analyze STUDIO/replicate/lora",
      container: { bus: nil, session: nil },
    )

    assert_equal "review", inferred[:command]
    assert_equal "STUDIO/replicate/lora", inferred[:args]
    assert_equal "/review STUDIO/replicate/lora",
                 Master::CLI::TurnRouter.rewrite_slash("/#{inferred[:command]} #{inferred[:args]}")
  end

end
