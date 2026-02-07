# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestStages < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
  end

  def test_preprocessor_with_string
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call("What is the meaning of life?")
    
    assert result.ok?
    assert_equal :question, result.value[:intent]
    assert result.value[:text], "Should have compressed text"
  end

  def test_preprocessor_with_hash
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call({ text: "Refactor this code" })
    
    assert result.ok?
    assert_equal :refactor, result.value[:intent]
  end

  def test_preprocessor_extracts_entities
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call("Check the pf firewall and httpd server")
    
    assert result.ok?
    assert result.value[:entities][:services], "Should extract service names"
  end

  def test_preprocessor_loads_axioms
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call({ text: "test" })
    
    assert result.ok?
    assert result.value[:axioms], "Should load axioms"
    assert result.value[:axioms].length > 0, "Should have axioms loaded"
  end

  def test_adversarial_review_loads_members
    stage = MASTER::Stages::AdversarialReview.new
    result = stage.call({ text: "test proposal" })
    
    assert result.ok?
    assert result.value[:council_responses], "Should have council responses"
    assert result.value[:consensus_reached], "Should reach consensus (stubbed)"
  end

  def test_adversarial_review_checks_threshold
    stage = MASTER::Stages::AdversarialReview.new
    result = stage.call({ text: "test" })
    
    assert result.ok?
    assert result.value[:consensus_score], "Should calculate consensus score"
  end

  def test_adversarial_review_checks_axioms
    stage = MASTER::Stages::AdversarialReview.new
    result = stage.call({ text: "clean code" })
    
    assert result.ok?
    assert result.value[:axioms_checked], "Should check axioms"
  end

  def test_postprocessor_typesetting
    stage = MASTER::Stages::Postprocessor.new
    result = stage.call({ text: 'Use "smart quotes" and -- em dashes...' })
    
    assert result.ok?
    assert result.value[:rendered], "Should have rendered output"
    assert_match(/\u{201C}/, result.value[:rendered], "Should convert quotes")
    assert_match(/\u{2014}/, result.value[:rendered], "Should convert dashes")
    assert_match(/\u{2026}/, result.value[:rendered], "Should convert ellipses")
  end

  def test_postprocessor_preserves_code
    stage = MASTER::Stages::Postprocessor.new
    input = { text: "Here is code:\n```ruby\nx = \"test\"\n```\nDone." }
    result = stage.call(input)
    
    assert result.ok?
    assert_match(/x = "test"/, result.value[:rendered], "Should preserve code")
  end

  def test_preprocessor_loads_zsh_patterns_for_command_intent
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call("create a new script")
    
    assert result.ok?
    assert result.value[:zsh_patterns], "Should load zsh patterns for command intent"
    assert result.value[:zsh_patterns].length > 0, "Should have zsh patterns loaded"
  end

  def test_preprocessor_loads_zsh_patterns_for_admin_intent
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call("configure pf firewall")
    
    assert result.ok?
    assert result.value[:zsh_patterns], "Should load zsh patterns for admin intent"
  end

  def test_preprocessor_loads_zsh_patterns_for_services
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call("check httpd status")
    
    assert result.ok?
    assert result.value[:zsh_patterns], "Should load zsh patterns when services detected"
  end

  def test_preprocessor_no_zsh_patterns_for_general
    stage = MASTER::Stages::Preprocessor.new
    result = stage.call("What is the weather?")
    
    assert result.ok?
    refute result.value[:zsh_patterns], "Should not load zsh patterns for general intent"
  end
end
