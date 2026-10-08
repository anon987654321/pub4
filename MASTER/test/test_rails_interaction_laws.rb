# frozen_string_literal: true

require_relative "test_helper"

class TestRailsInteractionLaws < Minitest::Test
  IDS = %w[
    DIRECT_MANIPULATION_FEEDBACK
    INTERACTION_PERFORMANCE
    STATE_CHOREOGRAPHY
    TACTILE_FEEDBACK
    POINTER_FEEDBACK_EARLY
    SIGNATURE_MOMENT
  ].freeze

  def test_interaction_laws_are_registered_and_part_of_visual_review
    context = Master::Fix::VisualUsability.context

    IDS.each do |id|
      law = Law.rules.fetch(id.to_sym) { flunk "#{id} is not registered" }
      assert_equal :opportunity, law.mode
      assert_includes law.path.to_s, "RAILS/"
      refute_empty law.ask.to_s
      refute_empty law.fix.to_s
      assert_includes Master::Fix::VisualUsability.ids, id
      assert_includes context, id
    end
  end
end
