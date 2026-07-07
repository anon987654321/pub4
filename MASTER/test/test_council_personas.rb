# frozen_string_literal: true

require_relative "test_helper"
require "judge/council/personas"
require "judge/council/selector"

class TestCouncilPersonas < Minitest::Test
  def test_loads_rich_personas_from_council_yaml
    names = Master::Judge::Council::Personas.load.map(&:name)

    assert_includes names, "NNGroup UX Researcher"
    assert_includes names, "Typographer"
    assert_includes names, "Cognitive Psychologist"
    assert_includes names, "Electronic Music Producer"
  end

  def test_ui_selector_includes_human_factors_personas
    names = Master::Judge::Council::Selector.for(task: :ui)

    assert_includes names, "Web Designer"
    assert_includes names, "Typographer"
    assert_includes names, "Cognitive Psychologist"
    assert_includes names, "NNGroup UX Researcher"
  end
end
