# frozen_string_literal: true

require_relative "test_helper"

class WorkflowInferenceTest < Minitest::Test
  def test_intent_router_classifies_through_master
    router = Master::Ground::IntentRouter.new
    assert_equal :run_full_workflow, router.classify("run this through master")
  end

  def test_intent_router_classifies_a_file_read
    router = Master::Ground::IntentRouter.new
    assert_equal :inspect_repo, router.classify("read CLAUDE.md")
    refute_equal :inspect_repo, router.classify("I read that the constitution is long")
    refute_equal :unknown, router.classify("read CLAUDE.md")
  end

  # /workflow is an alias of /through (see help.rb), so it renders the through
  # pipeline's sections. This test used to assert a "workflow: deliberation" /
  # "verdict:" shape from a design that no longer exists, and its doubles had
  # drifted from the real interfaces — FakeFixLoop had no #run and
  # FakeDeliberation had no #agent. Both crashes were swallowed into the report
  # as prose, so the only visible symptom was this assertion.
  def test_dispatch_workflow_renders_the_through_sequence
    out = dispatch(critique: false, apply: true)

    ["mode", "aesthetic scan", "deep scan", "fix", "re-scan", "principle map"].each do |section|
      assert_includes out, "# #{section}"
    end
    assert_match(/through\d+: complete/, out)
  end

  # --dry-run swaps the fix stage for a preview and drops the re-scan.
  def test_dry_run_previews_instead_of_fixing
    out = dispatch(critique: false)

    assert_includes out, "# fix preview"
    refute_includes out, "# re-scan"
  end

  def test_dispatch_workflow_reaches_deliberation_when_critique_is_on
    asked = []
    deliberation = FakeDeliberation.new(asked)
    out = dispatch(critique: true, deliberation:)

    assert_includes out, "# critique"
    refute_empty asked, "critique stage never reached the deliberation"
    refute_match(/NoMethodError/, out)
  end

  # The pipeline used to format a stage crash into the report and still print
  # "complete". A defect must escape; only operational failures degrade.
  def test_a_stage_defect_is_raised_not_formatted_into_the_report
    broken = Object.new
    def broken.run(_) = raise(NoMethodError, "undefined method 'run'")
    def broken.preview(_) = Master::Result.ok({ total: 0, rules: {}, files: {} })

    error = assert_raises(NoMethodError) { dispatch(critique: false, fix_loop: broken, apply: true) }
    assert_match(/undefined method/, error.message)
  end

  def test_an_operational_stage_failure_marks_the_run_incomplete
    flaky = Object.new
    def flaky.run(_) = raise(Errno::ENOENT, "scan target")
    def flaky.preview(_) = Master::Result.ok({ total: 0, rules: {}, files: {} })

    out = dispatch(critique: false, fix_loop: flaky, apply: true)

    assert_includes out, "fix failed: Errno::ENOENT"
    assert_match(/through\d+: incomplete — fix failed/, out)
    refute_includes out, "complete\n"
  end

  def dispatch(critique:, deliberation: FakeDeliberation.new([]), fix_loop: FakeFixLoop.new, apply: false)
    args = ["."]
    args << (apply ? "--apply" : "--dry-run")
    args << (critique ? "--critique" : "--no-critique")

    Master::CLI::CommandRegistry.stub(:dispatch_scan, ->(*, **) { "clean -- no violations" }) do
      Master::CLI::CommandRegistry.dispatch_workflow(
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
    def run(_target) = Master::Result.ok("fix: nothing to do")

    def preview(_target)
      Master::Result.ok({ total: 0, rules: {}, files: {} })
    end
  end
end
