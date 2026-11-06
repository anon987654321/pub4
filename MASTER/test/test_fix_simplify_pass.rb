# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop/council_round"

# The simplify pin: `/fix --simplify` swaps the council's critique contract
# for the quality-only one — reuse, simplification, efficiency and altitude,
# behavior preserved, no bug hunting. The instruments keep their findings.
class TestFixSimplifyPass < Minitest::Test
  def round
    Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: Master::ROOT)
  end

  def teardown
    Master::Fix::SimplifyPass.clear
  end

  def test_the_pin_is_off_by_default_and_requested_when_set
    refute_predicate Master::Fix::SimplifyPass, :requested?

    Master::Fix::SimplifyPass.set!
    assert_predicate Master::Fix::SimplifyPass, :requested?

    Master::Fix::SimplifyPass.clear
    refute_predicate Master::Fix::SimplifyPass, :requested?
  end

  def test_the_default_briefing_is_the_hard_review
    refute_includes round.send(:hard_briefing, []), "simplify critique"
  end

  def test_the_pin_swaps_the_contract_for_quality_only
    Master::Fix::SimplifyPass.set!
    briefing = round.send(:hard_briefing, [])

    assert_includes briefing, "This is the simplify critique"
    assert_includes briefing, "reuse"
    refute_includes briefing, "Attack the current design before proposing repairs"
    refute_includes briefing, "failure modes"
  end

  def test_the_pinned_briefing_keeps_its_anchoring_rows
    Master::Fix::SimplifyPass.set!
    briefing = round.send(:hard_briefing, [])

    assert_includes briefing, "repository-relative file plus a stable line or symbol"
    assert_includes briefing, "must preserve behavior"
  end
end
