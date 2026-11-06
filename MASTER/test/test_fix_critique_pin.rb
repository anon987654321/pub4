# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop/council_round"

# The critique pin: `/fix --simplify` and `/fix --security` swap the council's
# critique contract for the pinned one — quality-only, or the silently-failing
# properties. The deterministic instruments keep their findings either way.
class TestFixCritiquePin < Minitest::Test
  def round
    Master::Fix::FixLoop::CouncilRound.new(agent: nil, root: Master::ROOT)
  end

  def teardown
    Master::Fix::CritiquePin.clear
  end

  def test_the_pin_is_off_by_default_and_round_trips_through_its_foci
    refute_predicate Master::Fix::CritiquePin, :focus

    Master::Fix::CritiquePin.set!(:simplify)
    assert_equal :simplify, Master::Fix::CritiquePin.focus

    Master::Fix::CritiquePin.set!(:security)
    assert_equal :security, Master::Fix::CritiquePin.focus

    Master::Fix::CritiquePin.clear
    refute_predicate Master::Fix::CritiquePin, :focus
  end

  def test_an_unknown_focus_falls_back_to_no_pin
    Master::Fix::CritiquePin.set!(:wack)

    refute_predicate Master::Fix::CritiquePin, :focus
  end

  def test_the_default_briefing_is_the_hard_review
    refute_includes round.send(:hard_briefing, []), "simplify critique"
    refute_includes round.send(:hard_briefing, []), "security critique"
  end

  def test_the_simplify_pin_swaps_the_contract_for_quality_only
    Master::Fix::CritiquePin.set!(:simplify)
    briefing = round.send(:hard_briefing, [])

    assert_includes briefing, "This is the simplify critique"
    assert_includes briefing, "reuse"
    refute_includes briefing, "Attack the current design before proposing repairs"
    refute_includes briefing, "failure modes"
  end

  def test_the_security_pin_swaps_the_contract_for_silent_failures
    Master::Fix::CritiquePin.set!(:security)
    briefing = round.send(:hard_briefing, [])

    assert_includes briefing, "This is the security critique"
    assert_includes briefing, "custody"
    assert_includes briefing, "bypasses"
    refute_includes briefing, "Attack the current design before proposing repairs"
    refute_includes briefing, "This is the simplify critique"
  end

  def test_the_pinned_briefings_keep_their_anchoring_rows
    Master::Fix::CritiquePin.set!(:simplify)
    assert_includes round.send(:hard_briefing, []), "repository-relative file plus a stable line or symbol"
    assert_includes round.send(:hard_briefing, []), "must preserve behavior"

    Master::Fix::CritiquePin.set!(:security)
    assert_includes round.send(:hard_briefing, []), "repository-relative file plus a stable line or symbol"
    assert_includes round.send(:hard_briefing, []), "smallest deterministic check"
  end
end
