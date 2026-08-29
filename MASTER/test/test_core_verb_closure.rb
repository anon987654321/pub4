# frozen_string_literal: true

require "minitest/autorun"

require "master"

class VerbClosureTest < Minitest::Test
  CLOSED = Master::Core::VERBS.freeze

  def test_closed_verb_set_matches_proposal
    expected = %i[read write exec git ask note critique done]
    assert_equal expected.sort, CLOSED.sort
  end

  def test_model_system_prompt_lists_only_closed_verbs
    prompt = Master::Core::Model::SYSTEM
    %w[read write exec git ask note critique done].each do |verb|
      assert_match(/\b#{verb}\b/, prompt, "prompt must document #{verb}")
    end
  end
end
