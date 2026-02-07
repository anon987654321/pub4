# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require_relative "../lib/master"

class TestAudit < Minitest::Test
  def setup
    FileUtils.mkdir_p("tmp")
    @test_file = "tmp/test_audit_file.rb"
  end

  def teardown
    File.delete(@test_file) if File.exist?(@test_file)
  end

  def test_finding_struct
    finding = MASTER::Audit::Finding.new(
      file: "test.rb",
      line: 10,
      severity: :high,
      effort: :easy,
      category: :naming,
      message: "Bad name",
      suggestion: "Use better name"
    )
    
    assert_equal "test.rb", finding.file
    assert_equal :high, finding.severity
    assert_equal :easy, finding.effort
  end

  def test_report_add_finding
    report = MASTER::Audit::Report.new
    
    finding = MASTER::Audit::Finding.new(
      file: "test.rb",
      line: 1,
      severity: :medium,
      effort: :moderate,
      category: :test,
      message: "test",
      suggestion: nil
    )
    
    report.add(finding)
    assert_equal 1, report.findings.size
  end

  def test_report_prioritized_sorting
    report = MASTER::Audit::Report.new
    
    # Add findings with different priorities
    report.add(MASTER::Audit::Finding.new(
      file: "a.rb", line: 1, severity: :low, effort: :hard,
      category: :test, message: "Low priority", suggestion: nil
    ))
    
    report.add(MASTER::Audit::Finding.new(
      file: "b.rb", line: 1, severity: :critical, effort: :easy,
      category: :test, message: "High priority", suggestion: nil
    ))
    
    prioritized = report.prioritized
    
    # Critical/easy should come first
    assert_equal "High priority", prioritized.first.message
    assert_equal "Low priority", prioritized.last.message
  end

  def test_report_summary
    report = MASTER::Audit::Report.new
    
    report.add(MASTER::Audit::Finding.new(
      file: "a.rb", line: 1, severity: :high, effort: :easy,
      category: :naming, message: "test", suggestion: nil
    ))
    
    report.add(MASTER::Audit::Finding.new(
      file: "b.rb", line: 1, severity: :high, effort: :easy,
      category: :file_length, message: "test", suggestion: nil
    ))
    
    summary = report.summary
    
    assert_equal 2, summary[:total]
    assert_equal 2, summary[:by_severity][:high]
    assert_equal 1, summary[:by_category][:naming]
    assert_equal 1, summary[:by_category][:file_length]
  end

  def test_scan_detects_long_files
    # Create a long file
    content = "# frozen_string_literal: true\n" + ("puts 'line'\n" * 300)
    File.write(@test_file, content)
    
    result = MASTER::Audit.scan(@test_file)
    
    assert result.ok?
    report = result.value[:report]
    
    # Should detect file length issue
    length_findings = report.findings.select { |f| f.category == :file_length }
    assert length_findings.any?
  end

  def test_scan_detects_generic_verbs
    content = <<~RUBY
      # frozen_string_literal: true
      def handle_data
        puts "handling"
      end
    RUBY
    
    File.write(@test_file, content)
    
    result = MASTER::Audit.scan(@test_file)
    
    assert result.ok?
    report = result.value[:report]
    
    # Should detect generic verb "handle"
    naming_findings = report.findings.select { |f| f.category == :naming }
    assert naming_findings.any?
  end

  def test_scan_accepts_array_of_files
    result = MASTER::Audit.scan([@test_file])
    assert result.ok?
  end
end
