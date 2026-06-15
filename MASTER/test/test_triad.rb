# frozen_string_literal: true

require_relative "test_helper"

class TriadCommandTest < Minitest::Test
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

  def test_triad_runs_deliberation_not_review_toggle
    root = File.expand_path("../..", __dir__)
    out = Master::Now::CommandRegistry.dispatch_triad(
      scanner: FakeScanner.new,
      fix_loop: FakeFixLoop.new,
      council_stage: nil,
      deliberation: FakeDeliberation.new,
      root: root,
      bus: nil,
      review_crew: nil,
      ctx: { args: "." }
    )

    assert_includes out, "triad: deliberation"
    refute_match(/review:\s+(on|off|enabled|disabled)/i, out)
    assert_includes out, "verdict:"
  end
end