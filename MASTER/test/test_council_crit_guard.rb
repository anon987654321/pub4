# frozen_string_literal: true

require_relative "test_helper"

# Deliberation#review is where every council path arrives. Without a provider
# key each persona call fails slowly and the council spends its whole budget
# before reporting a quorum it could never reach, which reads as a hang: a
# /through pass sat at "crit0 deliberation" for ten minutes and printed
# nothing. Refusing here is the difference between that and an answer.
class CouncilKeyGuardTest < Minitest::Test
  class LoudPersonaAgent
    def ask(*) = raise("no persona may be asked without a provider key")
    def respond_to_missing?(*) = true
  end

  def council
    personas = Master::Review::Council::Personas.load(Master::COUNCIL_PATH).first(1)
    refute_empty personas, "council.yml must carry at least one persona for this to mean anything"
    Master::Review::Council::Deliberation.new(personas:, agent: LoudPersonaAgent.new)
  end

  def test_no_provider_key_refuses_before_any_persona_is_asked
    result = Master.stub(:any_api_key_present?, false) { council.review("x = 1") }

    assert_predicate result, :err?
    assert_match(/provider key/, result.message)
  end

  def test_the_refusal_names_the_personas_case_too
    result = Master.stub(:any_api_key_present?, true) do
      Master::Review::Council::Deliberation.new(personas: [], agent: LoudPersonaAgent.new).review("x = 1")
    end

    assert_predicate result, :err?
  end
end
