# frozen_string_literal: true

require_relative "test_helper"

class TestLanguageAxioms < Minitest::Test
  def test_axioms_data_loads
    assert MASTER::LanguageAxioms.axioms_data.is_a?(Hash)
    assert MASTER::LanguageAxioms.axioms_data.key?("ruby")
    assert MASTER::LanguageAxioms.axioms_data.key?("universal")
  end

  def test_all_axioms_returns_all
    axioms = MASTER::LanguageAxioms.all_axioms
    assert axioms.is_a?(Array)
    assert axioms.size >= 78, "Expected at least 78 axioms, got #{axioms.size}"
    
    # Check structure
    first = axioms.first
    assert first.key?("id")
    assert first.key?("name")
    assert first.key?("language")
  end

  def test_axioms_for_language
    ruby_axioms = MASTER::LanguageAxioms.axioms_for("ruby")
    assert ruby_axioms.is_a?(Array)
    assert ruby_axioms.size >= 15, "Expected at least 15 Ruby axioms"
    
    universal_axioms = MASTER::LanguageAxioms.axioms_for("universal")
    assert universal_axioms.size >= 15, "Expected at least 15 universal axioms"
  end

  def test_languages_for_file
    # Ruby files
    assert_equal %w[ruby rails universal], MASTER::LanguageAxioms.languages_for_file("foo.rb")
    assert_equal %w[ruby rails universal], MASTER::LanguageAxioms.languages_for_file("Rakefile.rake")
    
    # Shell files
    assert_equal %w[zsh universal], MASTER::LanguageAxioms.languages_for_file("script.sh")
    assert_equal %w[zsh universal], MASTER::LanguageAxioms.languages_for_file("script.zsh")
    
    # JavaScript files
    assert_equal %w[javascript universal], MASTER::LanguageAxioms.languages_for_file("app.js")
    assert_equal %w[javascript universal], MASTER::LanguageAxioms.languages_for_file("component.tsx")
    
    # CSS files
    assert_equal %w[css_scss universal], MASTER::LanguageAxioms.languages_for_file("style.css")
    assert_equal %w[css_scss universal], MASTER::LanguageAxioms.languages_for_file("style.scss")
    
    # HTML files
    assert_equal %w[html_erb universal], MASTER::LanguageAxioms.languages_for_file("page.html")
    assert_equal %w[html_erb universal], MASTER::LanguageAxioms.languages_for_file("view.erb")
    
    # Unknown extension
    assert_equal %w[universal], MASTER::LanguageAxioms.languages_for_file("file.txt")
  end

  def test_check_ruby_safe_navigation
    code = <<~RUBY
      user && user.name
    RUBY
    
    violations = MASTER::LanguageAxioms.check(code, filename: "test.rb")
    assert violations.any? { |v| v[:axiom_id] == "safe_navigation_chain" }
  end

  def test_check_ruby_freeze_constants
    code = <<~RUBY
      COLORS = ["red", "green", "blue"]
    RUBY
    
    violations = MASTER::LanguageAxioms.check(code, filename: "test.rb")
    assert violations.any? { |v| v[:axiom_id] == "freeze_collection_constants" }
  end

  def test_check_javascript_optional_chaining
    code = <<~JS
      user && user.profile
    JS
    
    violations = MASTER::LanguageAxioms.check(code, filename: "test.js")
    assert violations.any? { |v| v[:axiom_id] == "optional_chaining" }
  end

  def test_check_zsh_quote_variables
    code = <<~SH
      echo $USER
    SH
    
    violations = MASTER::LanguageAxioms.check(code, filename: "test.sh")
    assert violations.any? { |v| v[:axiom_id] == "quote_variables" }
  end

  def test_check_universal_typographic_excellence
    code = <<~TEXT
      "..."
    TEXT
    
    violations = MASTER::LanguageAxioms.check(code, filename: "test.rb")
    assert violations.any? { |v| v[:axiom_id] == "typographic_excellence" }
  end

  def test_check_skips_null_detect_patterns
    # Ensure axioms with null detect patterns don't crash
    code = "def foo; end"
    violations = MASTER::LanguageAxioms.check(code, filename: "test.rb")
    
    # Should not raise error, and return some violations
    assert violations.is_a?(Array)
  end

  def test_summary
    summary = MASTER::LanguageAxioms.summary
    assert summary.key?("ruby")
    assert summary.key?("universal")
    assert summary.key?("total")
    assert summary["total"] >= 78
  end

  def test_violation_structure
    code = "user && user.name"
    violations = MASTER::LanguageAxioms.check(code, filename: "test.rb")
    
    violation = violations.first
    assert violation[:layer] == :language_axiom
    assert violation.key?(:language)
    assert violation.key?(:axiom_id)
    assert violation.key?(:axiom_name)
    assert violation.key?(:message)
    assert violation.key?(:severity)
    assert violation.key?(:autofix)
    assert violation.key?(:file)
  end

  def test_enforcement_integration
    # Test that enforcement module includes language_axiom layer
    assert MASTER::Enforcement::LAYERS.include?(:language_axiom)
    
    # Test that check method works with language axioms
    code = "user && user.name"
    result = MASTER::Enforcement.check(code, filename: "test.rb")
    
    assert result.key?(:violations)
    assert result[:violations].any? { |v| v[:layer] == :language_axiom }
  end

  def test_autofix_marked_correctly
    ruby_axioms = MASTER::LanguageAxioms.axioms_for("ruby")
    
    # Check that some axioms are marked as autofix
    safe_nav = ruby_axioms.find { |a| a["id"] == "safe_navigation_chain" }
    assert safe_nav, "safe_navigation_chain axiom not found"
    assert safe_nav["autofix"] == true
    
    # Check that some are not
    guard = ruby_axioms.find { |a| a["id"] == "guard_clause_over_nested" }
    assert guard, "guard_clause_over_nested axiom not found"
    assert guard["autofix"] == false
  end
end
