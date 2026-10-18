# frozen_string_literal: true

require_relative "test_helper"
require "fix/scanner"
require "json"

class TestExternalLinterLaws < Minitest::Test
  def with_rubocop_report(stdout:, stderr: "", exitstatus: 0)
    status = Struct.new(:exitstatus).new(exitstatus)
    capture = ->(*_args, **_options) { [stdout, stderr, status] }
    rule = Master::Review::Scan::Laws::RubocopLaw.new(root: Master::ROOT)

    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, capture) { yield rule }
      end
    end
  end

  def test_empty_stdout_is_a_finding_not_a_clean_lint_result
    with_rubocop_report(stdout: "", stderr: "process failed", exitstatus: 1) do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/scan error/, findings.first.message)
      assert_match(/empty JSON stdout/, findings.first.message)
    end
  end

  def test_malformed_json_is_a_finding_not_a_clean_lint_result
    with_rubocop_report(stdout: "{not json") do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/scan error/, findings.first.message)
      assert_match(/invalid JSON stdout/, findings.first.message)
    end
  end

  def test_valid_offense_report_survives_linter_exit_status_one
    report = JSON.generate(
      "files" => [{
        "offenses" => [{
          "location" => { "line" => 2 },
          "cop_name" => "Style/Example",
          "message" => "example offense"
        }]
      }]
    )

    with_rubocop_report(stdout: report, exitstatus: 1) do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_equal 2, findings.first.line
      assert_match(/Style\/Example/, findings.first.message)
    end
  end
end
