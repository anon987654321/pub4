# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestPreservationRules < Minitest::Test
  def test_constitution_has_preserve_section
    rules = MASTER::Constitution.rules
    
    assert rules.key?("preserve"), "Constitution should have preserve section"
    assert rules["preserve"].key?("boot_message"), "Should have boot_message preservation rules"
    assert rules["preserve"].key?("diagnostic_output"), "Should have diagnostic_output preservation rules"
    assert rules["preserve"].key?("help_text"), "Should have help_text preservation rules"
  end

  def test_boot_message_preservation
    preserve = MASTER::Constitution.rules["preserve"]
    boot_msg = preserve["boot_message"]
    
    assert_equal "5-line OpenBSD dmesg style", boot_msg["format"]
    assert_equal "Diagnostic output - verbose is correct", boot_msg["reason"]
    assert_equal "Collapse to single cryptic line", boot_msg["never"]
  end

  def test_diagnostic_output_preservation
    preserve = MASTER::Constitution.rules["preserve"]
    diagnostic = preserve["diagnostic_output"]
    
    assert_equal "Structured multi-line output is intentional", diagnostic["rule"]
    assert_equal "Compress to cryptic abbreviations", diagnostic["never"]
  end

  def test_help_text_preservation
    preserve = MASTER::Constitution.rules["preserve"]
    help_text = preserve["help_text"]
    
    assert_equal "Help must be scannable and complete", help_text["rule"]
    assert help_text["minimum_info"].is_a?(Array)
    assert_includes help_text["minimum_info"], "Command name and syntax"
    assert_includes help_text["minimum_info"], "Brief description"
    assert_includes help_text["minimum_info"], "At least one example"
  end

  def test_spinner_feedback_preservation
    preserve = MASTER::Constitution.rules["preserve"]
    spinner = preserve["spinner_feedback"]
    
    assert_equal "Progress indicators show elapsed time and status", spinner["rule"]
  end

  def test_polish_rules_preservation
    preserve = MASTER::Constitution.rules["preserve"]
    polish_rules = preserve["polish_rules"]
    
    assert polish_rules.is_a?(Array)
    assert_includes polish_rules, "'Streamline' means remove redundancy, not information"
    assert_includes polish_rules, "'Polish' means refine wording, not delete output"
    assert_includes polish_rules, "'Minimize' applies to tokens in prompts, not diagnostic output"
  end
end
