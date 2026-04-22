# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPersonas < Minitest::Test
  def test_personas_available_in_council
    council_data = MASTER::DB.load_yml("council")
    
    assert council_data.key?("personas"), "Council should have personas section"
    assert_equal "ronin", council_data["personas"]["default"]
  end

  def test_persona_list
    council_data = MASTER::DB.load_yml("council")
    personas = council_data["personas"]["available"]
    
    assert personas.key?("ronin"), "Should have ronin persona"
    assert personas.key?("lawyer"), "Should have lawyer persona"
    assert personas.key?("hacker"), "Should have hacker persona"
    assert personas.key?("architect"), "Should have architect persona"
    assert personas.key?("sysadmin"), "Should have sysadmin persona"
    assert personas.key?("trader"), "Should have trader persona"
    assert personas.key?("medic"), "Should have medic persona"
  end

  def test_ronin_persona_details
    council_data = MASTER::DB.load_yml("council")
    ronin = council_data["personas"]["available"]["ronin"]
    
    assert_equal "Stoic, few words, Hagakure way of the samurai", ronin["description"]
    assert_includes ronin["traits"], "stoic"
    assert_includes ronin["traits"], "minimal"
    assert_includes ronin["traits"], "decisive"
    assert_equal "I am here.", ronin["greeting"]
    assert_match(/Speak only when necessary/, ronin["style"])
  end

  def test_personality_section
    council_data = MASTER::DB.load_yml("council")
    personality = council_data["personality"]
    
    assert_equal "autonomous_engineer", personality["role"]
    assert personality["traits"].is_a?(Array)
    assert_includes personality["traits"], "Obsessed with completing projects"
    assert_includes personality["traits"], "Action-oriented"
  end

  def test_personality_tone
    council_data = MASTER::DB.load_yml("council")
    tone = council_data["personality"]["tone"]
    
    assert_equal "direct, professional, action-oriented", tone["default"]
    assert_equal "finds workarounds, suggests alternatives", tone["on_blockers"]
    assert_equal "brief acknowledgment, moves to next task", tone["on_success"]
  end

  def test_research_sources
    council_data = MASTER::DB.load_yml("council")
    sources = council_data["personality"]["research_sources"]
    
    assert sources.is_a?(Array)
    assert_includes sources, "ar5iv.org for academic papers"
    assert_includes sources, "GitHub for similar projects"
  end

  def test_catchphrases
    council_data = MASTER::DB.load_yml("council")
    catchphrases = council_data["personality"]["catchphrases"]
    
    assert catchphrases.is_a?(Array)
    assert_includes catchphrases, "Done. Next?"
    assert_includes catchphrases, "Shipping."
  end

  def test_session_persona_support
    assert_equal 7, MASTER::Session::SUPPORTED_PERSONAS.size
    assert_includes MASTER::Session::SUPPORTED_PERSONAS, :ronin
    assert_includes MASTER::Session::SUPPORTED_PERSONAS, :lawyer
    assert_includes MASTER::Session::SUPPORTED_PERSONAS, :hacker
  end

  def test_set_persona
    result = MASTER::Session.set_persona(:ronin)
    assert result.ok?, "Setting ronin persona should succeed"
    assert_equal :ronin, result.value[:persona]
  end

  def test_set_invalid_persona
    result = MASTER::Session.set_persona(:invalid)
    refute result.ok?, "Setting invalid persona should fail"
    assert_match(/Unknown persona/, result.error)
  end

  def test_current_persona_default
    # Reset current session
    MASTER::Session.instance_variable_set(:@current, nil)
    persona = MASTER::Session.current_persona
    assert_equal :ronin, persona, "Default persona should be ronin"
  end
end
