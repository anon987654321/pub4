# frozen_string_literal: true

require "test_helper"

class OperatorModeTest < Minitest::Test
  def test_risk_maps_to_explicit_modes
    assert_equal :observe, Master::Operator::Mode.for(:low)
    assert_equal :plan, Master::Operator::Mode.for(:medium)
    assert_equal :repair, Master::Operator::Mode.for(:high)
    assert_equal :deploy, Master::Operator::Mode.for(:critical)
  end

  def test_observe_and_plan_have_no_mutation
    refute Master::Operator::Mode.capabilities(:observe).allow?(:write)
    refute Master::Operator::Mode.capabilities(:observe).allow?(:execute)
    refute Master::Operator::Mode.capabilities(:plan).allow?(:write)
    assert Master::Operator::Mode.capabilities(:plan).allow?(:model)
    assert Master::Operator::Mode.capabilities(:repair).allow?(:write)
    assert Master::Operator::Mode.capabilities(:deploy).allow?(:deploy)
  end

  def test_assessment_uses_existing_risk_router
    assessed = Master::Operator::Mode.assess("check the code", root: Master::ROOT)
    assert_equal :observe, assessed[:mode]
    assert_equal :low, assessed[:risk]
    assert_equal :cheap, assessed[:model_tier]
    refute assessed[:council_required]
  end
end
