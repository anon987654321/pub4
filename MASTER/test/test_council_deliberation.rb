# frozen_string_literal: true

require_relative "test_helper"

class TestCouncilDeliberation < Minitest::Test
  Persona = Struct.new(:name, :role, :bias, :prompt, :veto_role, :emphasizes, keyword_init: true) do
    def veto? = !!veto_role
  end

  class StubAgent
    def initialize(mapping = {})
      @mapping = mapping
    end

    def ask(prompt)
      @mapping.each do |needle, response|
        return response if prompt.include?(needle)
      end
      "looks good"
    end
  end

  def test_veto_blocks_review
    personas = [
      Persona.new(name: "Security", role: "Attacker", bias: "paranoid", prompt: "be strict", veto_role: true)
    ]
    agent = StubAgent.new("You are Security" => "VETO: unsafe eval path")

    result = Master::Council::Deliberation.new(personas:, agent:, judge_enabled: false)
                                        .review("eval(params[:x])")

    assert result.err?
    assert_equal :validation, result.category
    assert_match(/veto/i, result.message)
  end

  def test_empty_personas_fails_validation
    result = Master::Council::Deliberation.new(personas: [], agent: StubAgent.new, judge_enabled: false)
                                        .review("puts :ok")

    assert result.err?
    assert_equal :validation, result.category
    assert_match(/no personas/, result.message)
  end
end
