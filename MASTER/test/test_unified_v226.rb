#!/usr/bin/env ruby
# frozen_string_literal: true

# Comprehensive test for MASTER v226 Unified Framework

require_relative '../lib/master'
require_relative '../lib/unified/mood_indicator'
require_relative '../lib/unified/personas'
require_relative '../lib/unified/bug_hunting'
require_relative '../lib/unified/resilience'
require_relative '../lib/unified/systematic'

class UnifiedFrameworkTest
  def initialize
    @passed = 0
    @failed = 0
  end

  def assert(name, condition)
    if condition
      @passed += 1
      puts "  ✓ #{name}"
    else
      @failed += 1
      puts "  ✗ #{name}"
    end
  end

  def run
    puts "MASTER v226 Unified Framework Tests\n\n"

    test_postpro_enhancements
    test_mood_indicator
    test_personas
    test_bug_hunting
    test_resilience
    test_systematic
    test_configuration

    puts "\n#{@passed} passed, #{@failed} failed"
    exit(@failed > 0 ? 1 : 0)
  end

  def test_postpro_enhancements
    puts "Postpro Enhancements:"
    
    # Test new stocks
    assert "ilford_hp5 stock exists", MASTER::Postpro::STOCKS.key?(:ilford_hp5)
    assert "portra_400 stock exists", MASTER::Postpro::STOCKS.key?(:portra_400)
    assert "portra_800 stock exists", MASTER::Postpro::STOCKS.key?(:portra_800)
    assert "cinestill_50d stock exists", MASTER::Postpro::STOCKS.key?(:cinestill_50d)
    
    # Test new presets
    assert "cyberpunk preset exists", MASTER::Postpro::PRESETS.key?(:cyberpunk)
    assert "vintage_home_video preset exists", MASTER::Postpro::PRESETS.key?(:vintage_home_video)
    assert "lomography preset exists", MASTER::Postpro::PRESETS.key?(:lomography)
    assert "documentary preset exists", MASTER::Postpro::PRESETS.key?(:documentary)
    
    # Test metadata
    hp5 = MASTER::Postpro::STOCKS[:ilford_hp5]
    assert "ilford_hp5 has manufacturer", hp5[:manufacturer] == 'Ilford'
    assert "ilford_hp5 has year", hp5[:year] == 1931
    assert "ilford_hp5 has format", hp5[:format] == 'black_white'
    
    # Test list methods
    presets_list = MASTER::Postpro.list_presets
    assert "list_presets returns string", presets_list.is_a?(String)
    assert "list_presets includes cyberpunk", presets_list.include?('cyberpunk')
  end

  def test_mood_indicator
    puts "\nMood Indicator:"
    
    mood = MASTER::Unified::MoodIndicator.new(output: StringIO.new)
    
    assert "mood initializes", mood.is_a?(MASTER::Unified::MoodIndicator)
    assert "has idle mood", MASTER::Unified::MoodIndicator::MOODS.key?(:idle)
    assert "has thinking mood", MASTER::Unified::MoodIndicator::MOODS.key?(:thinking)
    assert "has working mood", MASTER::Unified::MoodIndicator::MOODS.key?(:working)
    assert "has success mood", MASTER::Unified::MoodIndicator::MOODS.key?(:success)
    assert "has error mood", MASTER::Unified::MoodIndicator::MOODS.key?(:error)
    
    mood.set(:thinking)
    assert "can set mood", mood.current_mood == :thinking
  end

  def test_personas
    puts "\nPersona Modes:"
    
    persona = MASTER::Unified::PersonaMode.new
    
    assert "persona initializes", persona.is_a?(MASTER::Unified::PersonaMode)
    assert "has ronin mode", MASTER::Unified::PersonaMode::MODES.key?(:ronin)
    assert "has verbose mode", MASTER::Unified::PersonaMode::MODES.key?(:verbose)
    assert "has hacker mode", MASTER::Unified::PersonaMode::MODES.key?(:hacker)
    assert "has poet mode", MASTER::Unified::PersonaMode::MODES.key?(:poet)
    assert "has detective mode", MASTER::Unified::PersonaMode::MODES.key?(:detective)
    
    assert "can switch to ronin", persona.switch(:ronin)
    assert "ronin is current", persona.current_mode == :ronin
    assert "ronin has terse style", persona.style == "terse"
  end

  def test_bug_hunting
    puts "\nBug Hunting Protocol:"
    
    file = File.expand_path('../lib/postpro.rb', __dir__)
    result = MASTER::Unified::BugHunting.analyze_file(file)
    
    assert "bug hunting returns hash", result.is_a?(Hash)
    assert "has file key", result.key?(:file)
    assert "has phases key", result.key?(:phases)
    assert "has 8 phases", result[:phases].keys.length == 8
    assert "has total_issues key", result.key?(:total_issues)
    assert "has severity key", result.key?(:severity)
  end

  def test_resilience
    puts "\nResilience Engine:"
    
    engine = MASTER::Unified::Resilience.new
    
    assert "engine initializes", engine.is_a?(MASTER::Unified::Resilience)
    assert "state is active", engine.state == :active
    assert "attempts starts at 0", engine.attempts.length == 0
    
    five_whys = engine.five_whys("test problem")
    assert "five_whys returns hash", five_whys.is_a?(Hash)
    assert "five_whys has technique", five_whys[:technique] == "Five Whys"
    assert "five_whys has questions", five_whys[:questions].is_a?(Array)
    
    rubber_duck = engine.rubber_duck("code")
    assert "rubber_duck returns hash", rubber_duck.is_a?(Hash)
  end

  def test_systematic
    puts "\nSystematic Protocols:"
    
    file = File.expand_path('../lib/postpro.rb', __dir__)
    result = MASTER::Unified::Systematic.before_edit(file)
    
    assert "before_edit returns hash", result.is_a?(Hash)
    assert "has pattern key", result[:pattern] == "clean"
    assert "has file key", result.key?(:file)
    assert "has lines key", result.key?(:lines)
    assert "has message key", result.key?(:message)
  end

  def test_configuration
    puts "\nConfiguration:"
    
    config_file = File.expand_path('../config/master_v226.yml', __dir__)
    assert "config file exists", File.exist?(config_file)
    
    config = YAML.load_file(config_file)
    assert "config loads", config.is_a?(Hash)
    assert "has meta section", config.key?('meta')
    assert "has constitutional_ai section", config.key?('constitutional_ai')
    assert "has bug_hunting_protocol section", config.key?('bug_hunting_protocol')
    assert "has resilience_engine section", config.key?('resilience_engine')
    assert "has systematic_protocols section", config.key?('systematic_protocols')
    assert "has principles section", config.key?('principles')
    
    assert "version is 226.0.0", config['meta']['version'] == "226.0.0"
    assert "codename is Unified Deep Debug", config['meta']['codename'] == "Unified Deep Debug"
  end
end

UnifiedFrameworkTest.new.run
