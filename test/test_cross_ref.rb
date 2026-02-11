# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../lib/master"

class TestCrossRef < Minitest::Test
  def setup
    FileUtils.mkdir_p("tmp")
    @test_file = "tmp/test_crossref.rb"
  end

  def teardown
    File.delete(@test_file) if File.exist?(@test_file)
  end

  def test_analyzer_initialization
    analyzer = MASTER::CrossRef::Analyzer.new
    
    assert_respond_to analyzer, :constant_defs
    assert_respond_to analyzer, :constant_uses
    assert_respond_to analyzer, :method_defs
    assert_respond_to analyzer, :method_calls
  end

  def test_analyze_file_with_constants
    content = <<~RUBY
      MAX_SIZE = 100
      puts MAX_SIZE
    RUBY
    
    File.write(@test_file, content)
    
    analyzer = MASTER::CrossRef::Analyzer.new
    result = analyzer.analyze(@test_file)
    
    assert result.ok?
    assert analyzer.constant_defs.key?("MAX_SIZE")
    assert analyzer.constant_uses.key?("MAX_SIZE")
  end

  def test_analyze_file_with_methods
    content = <<~RUBY
      def hello
        puts "world"
      end
      
      hello()
    RUBY
    
    File.write(@test_file, content)
    
    analyzer = MASTER::CrossRef::Analyzer.new
    result = analyzer.analyze(@test_file)
    
    assert result.ok?
    assert analyzer.method_defs.key?("hello")
    assert analyzer.method_calls.key?("hello")
  end

  def test_unused_constants_detection
    content = <<~RUBY
      UNUSED = 42
      USED = 100
      puts USED
    RUBY
    
    File.write(@test_file, content)
    
    analyzer = MASTER::CrossRef::Analyzer.new
    analyzer.analyze(@test_file)
    
    unused = analyzer.unused_constants
    
    assert_includes unused, "UNUSED"
    refute_includes unused, "USED"
  end

  def test_uncalled_methods_detection
    content = <<~RUBY
      def called_method
        puts "called"
      end
      
      def uncalled_method
        puts "never called"
      end
      
      called_method()
    RUBY
    
    File.write(@test_file, content)
    
    analyzer = MASTER::CrossRef::Analyzer.new
    analyzer.analyze(@test_file)
    
    uncalled = analyzer.uncalled_methods
    
    assert_includes uncalled, "uncalled_method"
    refute_includes uncalled, "called_method"
  end

  def test_to_audit_report
    content = <<~RUBY
      UNUSED = 42
      def unused_method
        puts "test"
      end
    RUBY
    
    File.write(@test_file, content)
    
    analyzer = MASTER::CrossRef::Analyzer.new
    analyzer.analyze(@test_file)
    
    report = analyzer.to_audit_report
    
    assert_respond_to report, :findings
    assert report.findings.size > 0
  end

  def test_analyze_accepts_array
    analyzer = MASTER::CrossRef::Analyzer.new
    result = analyzer.analyze([@test_file])
    
    assert result.ok?
  end
end
