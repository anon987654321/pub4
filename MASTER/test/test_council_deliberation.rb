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

    def ask(prompt, **)
      @mapping.each do |needle, response|
        return response if prompt.include?(needle)
      end
      "looks good"
    end
  end

  # Stubbed, not inherited: review refuses without a provider key, and keys
  # reach ENV through EnvLoader at boot — which neither tests nor bare
  # requires run. This test failed on any shell without exported keys and
  # passed on any with them, which is an environment reading, not a test.
  def test_veto_blocks_review
    personas = [
      Persona.new(name: "Security", role: "Attacker", bias: "paranoid", prompt: "be strict", veto_role: true),
    ]
    agent = StubAgent.new("You are Security" => "VETO: unsafe eval path")

    result = Master.stub(:any_api_key_present?, true) do
      Master::Review::Council::Deliberation.new(personas:, agent:, judge_enabled: false)
                                           .review("eval(params[:x])")
    end

    assert result.err?
    assert_equal :validation, result.category
    assert_match(/veto/i, result.message)
  end

  def test_quorum_error_carries_the_failure_tally
    failing = Class.new do
      def ask(_prompt, **) = raise(StandardError, "Insufficient credits. Add more using https://openrouter.ai")
    end.new
    personas = Array.new(4) { |i| Persona.new(name: "P#{i}", role: "r", bias: "b", prompt: "p") }

    result = Master.stub(:any_api_key_present?, true) do
      Master::Review::Council::Deliberation.new(personas:, agent: failing, judge_enabled: false)
                                           .review("puts :ok")
    end

    assert result.err?
    assert_match(/quorum not reached \(0\/4\)/, result.message)
    assert_match(/4x insufficient_credits/, result.message, "the reason tally is the actionable half")
  end

  def test_empty_personas_fails_validation
    result = Master::Review::Council::Deliberation.new(personas: [], agent: StubAgent.new, judge_enabled: false)
                                        .review("puts :ok")

    assert result.err?
    assert_equal :validation, result.category
    assert_match(/no personas/, result.message)
  end
end
