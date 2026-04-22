# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestLanguageDetection < Minitest::Test
  def test_supported_languages_defined
    assert_equal 2, MASTER::Session::SUPPORTED_LANGUAGES.size
    assert_includes MASTER::Session::SUPPORTED_LANGUAGES, :english
    assert_includes MASTER::Session::SUPPORTED_LANGUAGES, :norwegian
  end

  def test_norwegian_rules_defined
    assert_equal 4, MASTER::Session::NORWEGIAN_RULES.size
    assert_includes MASTER::Session::NORWEGIAN_RULES, "Use bokmål, not nynorsk"
    assert_includes MASTER::Session::NORWEGIAN_RULES, "Avoid anglicisms when Norwegian words exist"
  end

  def test_detect_english_text
    text = "The quick brown fox jumps over the lazy dog"
    result = MASTER::Session.detect_language(text)
    
    assert result.ok?, "Language detection should succeed"
    assert_equal :english, result.value[:language]
    assert result.value[:confidence] > 0.5
  end

  def test_detect_norwegian_text
    text = "Dette er en test med norske ord som og men er på"
    result = MASTER::Session.detect_language(text)
    
    assert result.ok?, "Language detection should succeed"
    assert_equal :norwegian, result.value[:language]
    assert result.value[:confidence] > 0.5
  end

  def test_detect_mixed_text_english_dominant
    text = "This is mostly English with a few norske ord"
    result = MASTER::Session.detect_language(text)
    
    assert result.ok?
    # Should detect as English since English words dominate
    assert_equal :english, result.value[:language]
  end

  def test_detect_mixed_text_norwegian_dominant
    text = "Dette er mest norsk med some English words"
    result = MASTER::Session.detect_language(text)
    
    assert result.ok?
    # Should detect as Norwegian since Norwegian words dominate
    assert_equal :norwegian, result.value[:language]
  end

  def test_detect_short_english_text
    text = "Hello world"
    result = MASTER::Session.detect_language(text)
    
    assert result.ok?
    assert_equal :english, result.value[:language]
  end

  def test_detect_short_norwegian_text
    text = "Hei på deg"
    result = MASTER::Session.detect_language(text)
    
    assert result.ok?
    assert_equal :norwegian, result.value[:language]
  end

  def test_norwegian_style_check_no_issues
    text = "Dette er en ren norsk tekst uten engelske ord"
    result = MASTER::Session.norwegian_style_check(text)
    
    assert result.ok?
    assert_equal 0, result.value[:issues].size
  end

  def test_norwegian_style_check_meeting_anglicism
    text = "Vi har et meeting i morgen"
    result = MASTER::Session.norwegian_style_check(text)
    
    assert result.ok?
    assert result.value[:issues].size > 0
    assert result.value[:issues].any? { |issue| issue.include?("meeting") && issue.include?("møte") }
  end

  def test_norwegian_style_check_deal_anglicism
    text = "Det var en god deal"
    result = MASTER::Session.norwegian_style_check(text)
    
    assert result.ok?
    assert result.value[:issues].size > 0
    assert result.value[:issues].any? { |issue| issue.include?("deal") && issue.include?("avtale") }
  end

  def test_norwegian_style_check_deadline_anglicism
    text = "Deadlinen er i neste uke"
    result = MASTER::Session.norwegian_style_check(text)
    
    assert result.ok?
    assert result.value[:issues].size > 0
    assert result.value[:issues].any? { |issue| issue.include?("deadline") && issue.include?("frist") }
  end

  def test_norwegian_style_check_feedback_anglicism
    text = "Jeg trenger feedback"
    result = MASTER::Session.norwegian_style_check(text)
    
    assert result.ok?
    assert result.value[:issues].size > 0
    assert result.value[:issues].any? { |issue| issue.include?("feedback") && issue.include?("tilbakemelding") }
  end

  def test_norwegian_style_check_multiple_anglicisms
    text = "Vi har et meeting for å diskutere dealen og feedbacken før deadline"
    result = MASTER::Session.norwegian_style_check(text)
    
    assert result.ok?
    assert result.value[:issues].size >= 4, "Should detect multiple anglicisms"
  end

  def test_norwegian_style_check_case_insensitive
    text = "Vi har et MEETING i morgen"
    result = MASTER::Session.norwegian_style_check(text)
    
    assert result.ok?
    assert result.value[:issues].size > 0, "Should detect anglicisms regardless of case"
  end

  def test_language_detection_confidence_score
    english_text = "The and but are on of to from with as that this"
    result = MASTER::Session.detect_language(english_text)
    
    assert result.ok?
    assert result.value[:confidence].is_a?(Float)
    assert result.value[:confidence] >= 0.0
    assert result.value[:confidence] <= 1.0
  end
end
