# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/routing/model_router/route_policy"

class TestRoutePolicy < Minitest::Test
  Policy = Master::CLI::Routing::RoutePolicy

  def decision(candidates:, reachable: nil, parked: [], usable: nil,
               recently_failed: [], meets_floor: [], local: [])
    reachable ||= candidates
    usable ||= candidates
    Policy.call(candidates:, reachable:, parked:, usable:, recently_failed:, meets_floor:, local:)
  end

  def test_candidate_ids_are_normalized_once_without_changing_order
    result = decision(candidates: [" opus ", "grok", "opus", nil, ""])

    assert_equal %w[opus grok], result.candidates
    assert_equal %w[opus grok], result.selected
    assert result.candidates.frozen?
    assert result.selected.frozen?
  end

  def test_nonrecent_answering_candidate_beats_floor_when_another_lane_failed
    result = decision(candidates: %w[opus grok], recently_failed: %w[opus], meets_floor: [])

    assert_equal %w[grok], result.selected
    assert_equal :answering_candidates, result.reason
  end

  def test_all_recent_failures_fall_back_to_floor_and_prefer_local_floor
    result = decision(
      candidates: %w[opus local],
      recently_failed: %w[opus local],
      meets_floor: %w[opus local],
      local: %w[local],
    )

    assert_equal %w[local], result.selected
    assert_equal :all_answering_candidates_recently_failed, result.reason
  end

  def test_all_recent_failures_without_floor_fail_closed
    result = decision(candidates: %w[opus grok], recently_failed: %w[opus grok])

    assert_empty result.selected
    assert_equal :recent_failures_without_floor, result.reason
  end

  def test_parked_candidates_never_enter_the_selected_route
    result = decision(candidates: %w[opus grok], parked: %w[opus])

    assert_equal %w[grok], result.selected
    assert_equal %w[opus], result.parked
  end

  def test_no_reachable_candidates_is_explicit
    result = decision(candidates: %w[opus grok], reachable: [])

    assert_empty result.selected
    assert_equal :no_reachable_candidates, result.reason
  end

  def test_unusable_candidates_remain_classified_for_offline_diagnostics
    result = decision(candidates: %w[opus], usable: [])

    assert_equal %w[opus], result.selected
    assert_equal :no_usable_candidates, result.reason
    assert_empty result.usable
  end
end
