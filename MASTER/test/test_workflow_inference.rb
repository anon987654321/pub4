# frozen_string_literal: true

require_relative "test_helper"

class WorkflowInferenceTest < Minitest::Test
  # A repair that says it repaired and shows nothing sends the operator to go
  # and look for it.
  def test_the_repair_shows_its_commits_and_its_patch
    pass = Master::CLI::Pipeline::Pass.allocate
    pass.instance_variable_set(:@root, Master::ROOT)
    fake = Object.new
    def fake.head = "abc1234"
    def fake.log_between(*) = ["abc1234 Master: a repair", "def5678 Master: another"]
    def fake.patch_between(*) = "diff --git a/x b/x\n@@ -1 +1 @@\n-old\n+new\n"
    def fake.working_patch(*) = ""
    pass.instance_variable_set(:@git, fake)

    section = pass.send(:changes_section, "abc1234")

    assert_includes section, "abc1234 Master: a repair"
    assert_includes section, "+new"
    assert_includes section, "-old"
  end

  def test_a_repair_that_changed_nothing_says_so
    pass = Master::CLI::Pipeline::Pass.allocate
    pass.instance_variable_set(:@root, Master::ROOT)
    quiet = Object.new
    def quiet.log_between(*) = []
    def quiet.patch_between(*) = ""
    def quiet.working_patch(*) = ""
    pass.instance_variable_set(:@git, quiet)

    assert_equal "nothing changed", pass.send(:changes_section, "abc1234")
  end

  def test_intent_router_classifies_through_master
    router = Master::CLI::IntentRouter.new
    assert_equal :run_full_workflow, router.classify("run this through master")
  end

  def test_intent_router_classifies_a_file_read
    router = Master::CLI::IntentRouter.new
    assert_equal :inspect_repo, router.classify("read CLAUDE.md")
    refute_equal :inspect_repo, router.classify("I read that the constitution is long")
    refute_equal :unknown, router.classify("read CLAUDE.md")
  end

  # /fix renders its lifecycle: what the tree says, what the repair did, and
  # what the tree says after. This test used to assert a "workflow:
  # deliberation" / "verdict:" shape from a design that no longer exists, and
  # its doubles had drifted from the real interfaces — FakeFixLoop had no #run
  # and FakeDeliberation had no #agent. Both crashes were swallowed into the
  # report as prose, so the only visible symptom was this assertion.
  def test_fix_renders_observe_repair_and_observe_again
    out = dispatch(critique: false, apply: true)

    ["mode", "observe", "repair", "re-observe"].each do |section|
      assert_includes out.lines.map(&:chomp), section
    end
    assert_match(/review\d+: complete/, out)
  end

  # The dmesg progress and the report print to one terminal, so the posture
  # line appears in exactly one of them.
  def test_the_posture_prints_once
    previous = ENV["MASTER_DMESG"]
    ENV["MASTER_DMESG"] = "1"
    posture = Master::Ground::ModePosture.new(root: File.expand_path("..", __dir__)).line
    printed, = capture_io { print dispatch(critique: false) }

    assert_equal 1, printed.scan(posture).size, printed
  ensure
    ENV["MASTER_DMESG"] = previous
  end

  # --dry-run reads and says what it would take on, then stops.
  def test_dry_run_says_what_it_would_repair_instead_of_repairing
    out = dispatch(critique: false)

    assert_includes out.lines.map(&:chomp), "observe"
    assert_includes out.lines.map(&:chomp), "would repair"
    refute_includes out.lines.map(&:chomp), "re-observe"
  end

  # /review is where the council is a stage of its own. Inside /fix it argues
  # per repair instead, which test_fix_council covers.
  def test_review_reaches_deliberation_when_critique_is_on
    asked = []
    deliberation = FakeDeliberation.new(asked)
    out = Master::CLI::CommandRegistry.stub(:observe, ->(*, **) { "clean -- no violations" }) do
      Master::CLI::CommandRegistry.dispatch_review(
        scanner: FakeScanner.new, fix_loop: FakeFixLoop.new, deliberation:,
        root: File.expand_path("..", __dir__), bus: nil, ctx: { args: ". --critique" },
      )
    end

    assert_includes out.lines.map(&:chomp), "critique"
    refute_empty asked, "critique stage never reached the deliberation"
    refute_match(/NoMethodError/, out)
  end

  # /review writes nothing, whatever it is asked: the verb that writes is /fix.
  def test_review_never_repairs
    out = Master::CLI::CommandRegistry.stub(:observe, ->(*, **) { "clean -- no violations" }) do
      Master::CLI::CommandRegistry.dispatch_review(
        scanner: FakeScanner.new, fix_loop: FakeFixLoop.new, deliberation: FakeDeliberation.new([]),
        root: File.expand_path("..", __dir__), bus: nil, ctx: { args: ". --apply --no-critique" },
      )
    end

    refute_includes out.lines.map(&:chomp), "repair"
    refute_includes out.lines.map(&:chomp), "re-observe"
  end

  # The pipeline used to format a stage crash into the report and still print
  # "complete". A defect must escape; only operational failures degrade.
  def test_a_stage_defect_is_raised_not_formatted_into_the_report
    broken = Object.new
    def broken.run(_, **) = raise(NoMethodError, "undefined method 'run'")
    def broken.preview(_) = Master::Result.ok({ total: 0, rules: {}, files: {} })

    error = assert_raises(NoMethodError) { dispatch(critique: false, fix_loop: broken, apply: true) }
    assert_match(/undefined method/, error.message)
  end

  def test_an_operational_stage_failure_marks_the_run_incomplete
    flaky = Object.new
    def flaky.run(_, **) = raise(Errno::ENOENT, "scan target")
    def flaky.preview(_) = Master::Result.ok({ total: 0, rules: {}, files: {} })

    out = dispatch(critique: false, fix_loop: flaky, apply: true)

    assert_includes out, "fix failed: Errno::ENOENT"
    assert_match(/review\d+: incomplete — fix failed/, out)
    refute_includes out, "complete\n"
  end

  def dispatch(critique:, deliberation: FakeDeliberation.new([]), fix_loop: FakeFixLoop.new, apply: false)
    args = ["."]
    args << (apply ? "--apply" : "--dry-run")
    args << (critique ? "--critique" : "--no-critique")

    Master::CLI::CommandRegistry.stub(:observe, ->(*, **) { "clean -- no violations" }) do
      Master::CLI::CommandRegistry.dispatch_fix(
        scanner: FakeScanner.new,
        fix_loop:,
        deliberation:,
        root: File.expand_path("..", __dir__),
        bus: nil,
        ctx: { args: args.join(" ") },
      )
    end
  end

  class FakeDeliberation
    def initialize(asked) = @asked = asked

    def agent = nil # lean boot: no agent, so critique takes the tribunal path

    def review_convergent(payload, context:)
      @asked << context
      Master::Result.ok([{ role: "Synthesis", feedback: "ok for #{payload.to_s[0, 20]}" }])
    end
  end

  class FakeScanner
    def scan(_path) = Master::Result.ok([])

    def scan_dir(_dir, depth: :deep, glob: nil, stream: false)
      Master::Result.ok([])
    end
  end

  class FakeFixLoop
    def run(_target, **) = Master::Result.ok("fix: nothing to do")

    def preview(_target)
      Master::Result.ok({ total: 0, rules: {}, files: {} })
    end
  end
end
