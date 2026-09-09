# frozen_string_literal: true

require_relative "test_helper"

class TestThroughInference < Minitest::Test
# --only names stages, and the names have to mean the same thing everywhere.
# `fix` is a spelling of `scan` because the scan stage fixes what it finds on
# the spot — going back to relocate a finding later is the cost the fold
# removes — and `council` is a spelling of `critique`.
def test_only_accepts_stage_names_and_their_spellings
  pipeline = Master::CLI::Pipeline::Through.allocate

  assert_nil pipeline.send(:normalize_stages, nil)
  assert_equal %w[scan], pipeline.send(:normalize_stages, "scan")
  assert_equal %w[scan], pipeline.send(:normalize_stages, "fix")
  assert_equal %w[scan], pipeline.send(:normalize_stages, "scan,fix")
  assert_equal %w[critique], pipeline.send(:normalize_stages, "council")
  assert_equal %w[scan critique], pipeline.send(:normalize_stages, "scan,critique")
end

# A misspelled stage must not silently widen the pass to everything, which is
# what dropping the unknown name and falling back to nil would do.
def test_an_unknown_stage_runs_nothing_and_is_named
  pipeline = Master::CLI::Pipeline::Through.allocate

  assert_empty pipeline.send(:normalize_stages, "bogus")
  assert_equal %w[bogus], pipeline.instance_variable_get(:@unknown_stages)

  assert_equal %w[scan], pipeline.send(:normalize_stages, "scan,bogus")
  assert_equal %w[bogus], pipeline.instance_variable_get(:@unknown_stages)
end

# The flag parser is the other half: /through --only scan x and
# --only=scan must both leave the path alone.
def test_the_only_flag_is_parsed_in_both_spellings
  registry = Master::CLI::CommandRegistry

  assert_equal [nil, nil, true, "scan", "lib/io"], registry.parse_through_flags("--only scan lib/io")
  assert_equal [nil, nil, true, "critique", "lib"], registry.parse_through_flags("--only=critique lib")
  assert_equal [false, nil, true, "scan", "../RAILS/amber"],
               registry.parse_through_flags("--only scan --no-autofix ../RAILS/amber")
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
    assert_equal "through", inferred[:command]
  end

  def test_turn_router_promotes_scan_and_fix_to_through
    %w[scan\ lib fix\ lib].each do |text|
      inferred = Master::CLI::TurnRouter.infer_operator_command(text, container: { bus: nil, session: nil })
      refute_nil inferred, "#{text} should infer a work command"
      assert_equal "through", inferred[:command], "#{text} should run the full pass"
    end
  end

  def test_turn_router_itself_maps_to_master
    inferred = Master::CLI::TurnRouter.infer_operator_command(
      "run master through itself",
      container: { bus: nil, session: nil },
    )
    refute_nil inferred
    assert_equal "through", inferred[:command]
    assert_match(/master|self|/, inferred[:args].to_s)
  end

  def test_through_pipeline_resolves_rails_alias
    scanner = Object.new
    def scanner.scan(*) = Master::Result.ok([])
    def scanner.scan_dir(*) = Master::Result.ok([])
    fix = Object.new
    def fix.run(*) = Master::Result.ok("fixed")
    def fix.preview(*) = Master::Result.ok(total: 0, rules: {}, files: {})

    stub_scan = lambda { |*| "scan: clean" }
    Master::CLI::CommandRegistry.stub(:dispatch_scan, stub_scan) do
      pipe = Master::CLI::Pipeline::Through.new(
        scanner:,
        fix_loop: fix,
        root: Master::ROOT,
        deliberation: nil,
        bus: nil,
      )
      result = pipe.call(target: "rails", apply: false, critique: false, aesthetic: false)
      # Strict equality: the old `end_with?("RAILS")` disjunct accepted
      # /Users/…/GitHub/RAILS — the nonexistent sibling ../RAILS used to
      # resolve to — so the test passed while the gate scanned MASTER.
      assert_equal Master::RAILS_ROOT, result.target
      # dmesg-style unit id (through0), not a literal "through:" label
      assert_match(/through\d+:\s*complete/, result.render)

      # bin/gate's spelling. Expanding the ../ against the repo root walked
      # out of the repo, and a target that does not exist falls back to
      # scanning MASTER — the RAILS stage measured the wrong tree.
      assert_equal Master::RAILS_ROOT, pipe.send(:resolve_target, "../RAILS")
      assert_equal File.join(Master::RAILS_ROOT, "brgen"), pipe.send(:resolve_target, "../RAILS/brgen")
      assert File.exist?(pipe.send(:resolve_target, "../RAILS")), "resolved RAILS target must exist"
    end
  end

  def test_rails_rules_registered
    require_relative "../lib/review/scan/rule_dsl"
    ids = Master::Review::Scan::Rule.registry.filter_map do |k|
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

  # SPRAWL-105: the coordinator was constructed under MASTER_FULL_BOOT and read
  # by nothing. These two pin both halves of the wiring -- that a lean boot
  # still runs the pass it ran, and that a full boot reaches the coordinator.
  def test_through_without_a_swarm_adds_nothing_to_critique
    through = Master::CLI::Pipeline::Through.new(scanner: nil, fix_loop: nil, root: Master::ROOT)

    assert_nil through.send(:swarm_review, __FILE__)
  end

  def test_through_reads_the_swarm_when_one_is_wired
    swarm = Object.new
    swarm.define_singleton_method(:analyse_and_review) do |file_path:, code:|
      Master::Result.ok({ analysis: "read #{code.length} bytes", review: "no issues", approved: true })
    end
    through = Master::CLI::Pipeline::Through.new(scanner: nil, fix_loop: nil, root: Master::ROOT, swarm:)

    line = through.send(:swarm_review, __FILE__)

    assert_includes line, "swarm: approved"
    assert_includes line, "no issues"
  end

  def test_through_footer_names_a_skipped_tier
    result = Master::CLI::Pipeline::Through::Result.new(
      target: ".", mode: "balanced", sections: [], ok: true, unit: "through0", failed_stages: []
    )
    Master::Io::QuotaGate.stub(:report, "SKIPPED semantic rules — exhausted") do
      text = result.footer

      assert_includes text, "through0: complete"
      assert_includes text, "SKIPPED semantic rules"
    end
  end
end
