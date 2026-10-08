# frozen_string_literal: true

require_relative "test_helper"

# Affect and SelfModel are the two bounded state tables Cognition::Mind updates
# on every perceived event. Bounded is the contract: a mood or a belief list
# that only accumulates ends up explaining everything.
class TestCognitionAffect < Minitest::Test
  def affect = Master::Cognition::Affect.new
  def self_model = Master::Cognition::SelfModel.new

  def test_an_outcome_moves_valence_by_its_fixed_step
    state = { "valence" => 0.0 }
    affect.update!(state, prediction_error: 0.5, salience: 0.0, success: false)

    assert_in_delta(-0.12, state["valence"])
    affect.update!(state, prediction_error: 0.5, salience: 0.0, success: true)
    assert_in_delta(-0.04, state["valence"])
  end

  def test_without_an_outcome_surprise_lowers_valence_and_confirmation_raises_it
    surprised = affect.update!({ "valence" => 0.0 }, prediction_error: 1.0, salience: 0.0)
    confirmed = affect.update!({ "valence" => 0.0 }, prediction_error: 0.0, salience: 0.0)

    assert_operator surprised["valence"], :<, 0.0
    assert_operator confirmed["valence"], :>, 0.0
  end

  def test_every_value_stays_in_bounds_under_repeated_extremes
    state = {}
    50.times { affect.update!(state, prediction_error: 9.0, salience: 9.0, success: true) }

    assert_equal 1.0, state["valence"]
    assert_operator state["arousal"], :<=, 1.0
    assert_equal 1.0, state["novelty"], "prediction error is clamped before it is stored"
    assert_operator state["uncertainty"], :<=, 1.0
  end

  def test_arousal_decays_toward_rest_with_nothing_happening
    state = { "arousal" => 1.0 }
    affect.update!(state, prediction_error: 0.0, salience: 0.0)

    assert_in_delta 0.82, state["arousal"]
  end

  def test_self_model_counts_events_and_keeps_consciousness_unknown
    model = {}
    2.times { self_model.update!(model, event: "tick", payload: { "n" => 1, "note" => "x" * 500 }, salience: 0.123456) }

    assert_equal 2, model.dig("event/tick", "count")
    assert_equal 0.1235, model.dig("event/tick", "salience")
    assert_equal 200, model["last_payload"]["note"].size
    assert_equal "unknown", model.dig("capabilities", "phenomenal_consciousness")
  end

  def test_self_model_prunes_to_the_newest_beliefs
    model = {}
    (Master::Cognition::SelfModel::MAX_BELIEFS + 5).times do |i|
      self_model.update!(model, event: "e#{i}", payload: nil, salience: 0.1)
      model["event/e#{i}"]["last_at"] = i
    end
    self_model.update!(model, event: "latest", payload: nil, salience: 0.1)

    assert_equal Master::Cognition::SelfModel::MAX_BELIEFS, model.keys.grep(%r{\Aevent/}).size
    refute model.key?("event/e0"), "the oldest belief is the one dropped"
  end

  def test_reflection_states_the_stance_and_the_numbers
    text = self_model.reflection({}, metrics: { "integration" => 0.5, "prediction_error" => 0.25 },
                                     affect: { "valence" => -0.1 })

    assert_equal "I am unknown about phenomenal consciousness; my integrated-state proxy is 0.5, " \
                 "prediction error 0.25, valence -0.1.", text
  end
end
