# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class TestSelfCheck < Minitest::Test
  def test_quick_reports_clean_on_empty_directory
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))

      report = Master::Fix::SelfCheck.new(root:).quick

      assert report.clean?
      assert_equal "selfcheck: clean", report.summary
      assert_nil report.error
    end
  end

  def test_quick_finds_error_severity_violations_only
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib", "bad.rb"), "def foo\n  begin\n  rescue\n    nil\n  end\nend\n")

      quick = Master::Fix::SelfCheck.new(root:).quick
      full = Master::Fix::SelfCheck.new(root:).full

      refute quick.clean?
      assert_includes quick.summary, "violation"
      assert_operator full.total, :>=, quick.total, "full scan should never find fewer violations than quick"
      assert quick.findings.any? { |item| item[:path].to_s.end_with?("bad.rb") && item[:line] },
             "a violation without a path and line is a count you cannot act on"
    end
  end

  def test_report_summary_reflects_a_scan_failure
    report = Master::Fix::SelfCheck::Report.new(total: 0, by_rule: {}, by_severity: {}, error: "boom", findings: [])

    refute report.clean?
    assert_equal "selfcheck: failed — boom", report.summary
  end
end
