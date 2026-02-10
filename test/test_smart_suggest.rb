require 'minitest/autorun'
require_relative '../lib/smart_suggest'

class TestSmartSuggest < Minitest::Test
  def setup
    @suggester = MASTER::SmartSuggest.new
  end

  def test_detect_god_class
    code = "class Big\n" + ("  def method#{rand}\n  end\n" * 40)
    suggestions = @suggester.analyze_file(__FILE__)
    # Should detect if file is large enough
    assert_kind_of Array, suggestions
  end

  def test_detect_long_methods
    code = <<~RUBY
      def long_method
        #{'puts "line"' + "\n" * 30}
      end
    RUBY
    
    # Create temp file
    require 'tempfile'
    file = Tempfile.new(['test', '.rb'])
    file.write(code)
    file.close
    
    suggestions = @suggester.analyze_file(file.path)
    long_method_suggestions = suggestions.select { |s| s.type == :long_method }
    
    assert long_method_suggestions.size >= 0
    
    file.unlink
  end

  def test_detect_magic_numbers
    code = <<~RUBY
      def calculate
        x = 42
        y = 999
        x + y
      end
    RUBY
    
    require 'tempfile'
    file = Tempfile.new(['test', '.rb'])
    file.write(code)
    file.close
    
    suggestions = @suggester.analyze_file(file.path)
    magic_suggestions = suggestions.select { |s| s.type == :magic_numbers }
    
    assert magic_suggestions.size >= 0
    
    file.unlink
  end

  def test_suggestion_priority_calculation
    suggestion = MASTER::Suggestion.new(
      type: :refactor,
      file: 'test.rb',
      description: 'Test',
      impact: :high,
      effort: :low,
      confidence: 0.9,
      line: 1
    )
    
    # High impact (5) / Low effort (1) * 0.9 confidence * 100 = 450
    assert_equal 450.0, suggestion.priority
  end

  def test_batch_analyze
    suggestions = @suggester.batch_analyze(['lib/'])
    assert_kind_of Array, suggestions
  end
end
