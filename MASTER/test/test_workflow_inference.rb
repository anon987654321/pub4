# frozen_string_literal: true

require_relative "test_helper"

class WorkflowInferenceTest < Minitest::Test
  def test_intent_router_classifies_through_master
    router = Master::Ground::IntentRouter.new
    assert_equal :run_full_workflow, router.classify("run this through master")
  end

  def test_dispatch_workflow_runs_deliberation_not_review_toggle
    root = File.expand_path("../..", __dir__)
    fake = FakeDeliberation.new
    out = Master::Now::CommandRegistry.dispatch_workflow(
      scanner: FakeScanner.new,
      fix_loop: FakeFixLoop.new,
      deliberation: fake,
      root: root,
      bus: nil,
      ctx: { args: "." }
    )
    assert_includes out, "workflow: deliberation"
    refute_match(/review:\s+(on|off)/i, out)
    assert_includes out, "verdict:"
  end

  class FakeDeliberation
    def review_convergent(_payload, context:)
      Master::Result.ok([{ role: "Synthesis", feedback: "ok for #{context}" }])
    end
  end

  class FakeScanner
    def scan(_path)
      "scan: ok"
    end
  end

  class FakeFixLoop
    def preview(_target)
      Master::Result.ok({ changes: [] })
    end
  end
end