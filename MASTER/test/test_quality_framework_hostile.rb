# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/review/council/quality_framework"

class QualityFrameworkHostileTest < Minitest::Test
  def test_red_team_questions_are_present
    questions = Master::Review::Council::QualityFramework.questions.fetch("red_team")
    assert_operator questions.length, :>=, 8
    assert_includes questions, "what observation would falsify your criticism?"
  end

  def test_hostile_questions_are_stable_and_persona_specific
    a = Data.define(:name).new("Graphic Designer")
    b = Data.define(:name).new("Security")

    first = Master::Review::Council::QualityFramework.hostile_questions(a)
    second = Master::Review::Council::QualityFramework.hostile_questions(a)
    other = Master::Review::Council::QualityFramework.hostile_questions(b)

    assert_equal first, second
    refute_equal first, other
    assert_equal 3, first.length
  end
end
