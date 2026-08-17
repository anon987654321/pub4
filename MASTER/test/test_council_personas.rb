# frozen_string_literal: true

require_relative "test_helper"
require "review/council/personas"
require "review/council/selector"

class TestCouncilPersonas < Minitest::Test
  def test_personas_carry_temperature_not_weight
    loaded = Master::Review::Council::Personas.load
    refute_includes Master::Review::Council::Personas::Persona.members, :weight
    security = loaded.find { |p| p.name == "Security" }
    user = loaded.find { |p| p.name == "User Advocate" }
    assert_in_delta 0.1, security.temperature, 0.001
    assert_operator user.temperature, :>, security.temperature
  end

  def test_ask_persona_forwards_temperature
    seen = nil
    agent = Object.new
    agent.define_singleton_method(:ask) { |_prompt, temperature: nil, **| seen = temperature; "ok" }
    persona = Master::Review::Council::Personas.load.find { |p| p.name == "Security" }
    delib = Master::Review::Council::Deliberation.new(personas: [persona], agent:, event_bus: nil)
    delib.send(:ask_persona, persona:, code: "x = 1", context: nil)
    assert_in_delta 0.1, seen, 0.001
  end

  def test_loads_rich_personas_from_council_yaml
    names = Master::Review::Council::Personas.load.map(&:name)

    assert_includes names, "NNGroup UX Researcher"
    assert_includes names, "Typographer"
    assert_includes names, "Cognitive Psychologist"
    assert_includes names, "Electronic Music Producer"
  end

  def test_ui_selector_includes_human_factors_personas
    names = Master::Review::Council::Selector.for(task: :ui)

    assert_includes names, "Web Designer"
    assert_includes names, "Typographer"
    assert_includes names, "Cognitive Psychologist"
    assert_includes names, "NNGroup UX Researcher"
  end

  def test_selector_unions_task_and_risk_instead_of_raising
    names = Master::Review::Council::Selector.for(task: :ui, risk: :high)

    assert_includes names, "Web Designer"
    assert_includes names, "Security"
    assert_includes names, "Maintainer"
  end

  def test_selector_available_filter_is_not_dead
    names = Master::Review::Council::Selector.for(
      task: :ui,
      available: ["Web Designer", "Maintainer", "Typographer"],
    )

    assert_equal ["Web Designer", "Typographer", "Maintainer"].sort, names.sort
  end

  # Critique.build_panel downcases preset names and keeps the intersection
  # with Personas.load. A name that is not a persona is dropped with no
  # warning, so motion_critique sat two hats and called itself five.
  def test_every_preset_panel_name_is_a_loaded_persona
    data = Master.load_yaml(Master::COUNCIL_PATH)
    known = Master::Review::Council::Personas.load.flat_map { |p|
      [p.name, *Array(p.aliases)]
    }.map { |n| n.to_s.downcase }
    missing = Array(data["presets"]).flat_map do |key, preset|
      Array(preset["panel"]).reject { |name| known.include?(name.to_s.downcase) }
                            .map { |name| "#{key}: #{name}" }
    end

    assert_empty missing,
                 "preset panel names with no persona (Critique.build_panel drops them):\n  #{missing.join("\n  ")}"
  end
end
