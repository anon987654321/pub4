# frozen_string_literal: true

require_relative "../test_helper"

class TestCouncilFace < Minitest::Test
  def test_for_architect_has_left_lane
    face = Master::Voice::CouncilFace.for_persona("Architect")
    assert_equal "Architect", face[:label]
    assert_equal :left, face[:position]
    assert_equal :left, face[:viseme_lane]
    assert face[:blendshapes].is_a?(Hash)
  end

  def test_for_skeptic_has_right_lane_and_policy_voice
    face = Master::Voice::CouncilFace.for_persona("Skeptic")
    assert_equal Master::Voice::Policy.single_voice_key, face[:voice]
    assert_equal :right, face[:viseme_lane]
  end

  def test_unknown_persona_falls_back_to_pragmatist
    face = Master::Voice::CouncilFace.for_persona("Unknown")
    assert_equal "Pragmatist", face[:label]
  end
end
