# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/routing/model_router/route_policy"
require_relative "../lib/cli/routing/model_router"

class TestRoutePolicy < Minitest::Test
  Policy = Master::CLI::Routing::RoutePolicy

  def decision(candidates:, reachable: nil, parked: [], usable: nil,
               recently_failed: [], meets_floor: [], local: [])
    reachable ||= candidates
    usable ||= candidates
    Policy.call(candidates:, reachable:, parked:, usable:, recently_failed:, meets_floor:, local:)
  end

  def test_router_selection_methods_are_owned_by_the_selection_module
    router = Master::CLI::Routing::ModelRouter

    assert_includes router.ancestors, router::Selection
    assert_equal router::Selection, router.instance_method(:preferred).owner
    assert_equal router::Selection, router.instance_method(:fallback_chain).owner
    assert_equal router::Selection, router.instance_method(:constrained_for).owner
  end

  def test_usable_candidates_are_preferred_over_unusable_candidates
    result = decision(
      candidates: %w[opus grok],
      usable: %w[grok],
      recently_failed: [],
    )

    assert_equal %w[grok], result.selected
    assert_equal :answering_candidates, result.reason
  end

  def test_all_parked_candidates_are_reported_as_parked
    result = decision(candidates: %w[opus grok], parked: %w[opus grok])

    assert_empty result.selected
    assert_equal %w[opus grok], result.parked
    assert_equal :all_candidates_parked, result.reason
  end

  def test_no_candidate_input_is_reported_without_inventing_a_route
    result = decision(candidates: [])

    assert_empty result.candidates
    assert_empty result.selected
    assert_equal :no_reachable_candidates, result.reason
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

  def test_unreadable_free_model_quota_parks_only_quota_tracked_lanes
    router = Master::CLI::Routing::ModelRouter.allocate
    quota_error = ->(_model, **) { raise IOError, "quota state corrupt" }

    Master::Io::ModelQuota.stub(:forecast, quota_error) do
      assert router.send(:unhealthy?, "google/gemma-4-31b-it:free")
      refute router.send(:unhealthy?, "claude-cli:claude-sonnet-5-5")
    end
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

  def test_only_reachable_candidates_participate_in_the_decision
    result = decision(
      candidates: %w[opus ghost grok],
      reachable: %w[opus grok],
      usable: %w[opus grok],
    )

    assert_equal %w[opus grok], result.reachable
    assert_equal %w[opus grok], result.selected
  end

  def test_unusable_floor_fallback_is_classified_for_offline_diagnostics
    result = decision(
      candidates: %w[opus grok],
      usable: %w[grok],
      recently_failed: %w[grok],
      meets_floor: %w[opus],
    )

    assert_equal %w[opus], result.selected
    assert_equal :no_usable_candidates, result.reason
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
    result = decision(
      candidates: %w[opus local],
      recently_failed: %w[opus local],
      meets_floor: %w[opus local],
      local: %w[local],
    )

    assert_equal %w[local], result.selected
    assert_equal :all_answering_candidates_recently_failed, result.reason
  end

  def test_only_reachable_candidates_participate_in_the_decision
    result = decision(
      candidates: %w[opus ghost grok],
      reachable: %w[opus grok],
      usable: %w[opus grok],
    )

    assert_equal %w[opus grok], result.reachable
    assert_equal %w[opus grok], result.selected
  end

  def test_unusable_floor_fallback_is_classified_for_offline_diagnostics
    result = decision(
      candidates: %w[opus grok],
      usable: %w[grok],
      recently_failed: %w[grok],
      meets_floor: %w[opus],
    )

    assert_equal %w[opus], result.selected
    assert_equal :no_usable_candidates, result.reason
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
