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

  def test_valid_json_with_the_wrong_rubocop_shape_is_not_clean
    with_rubocop_report(stdout: "null") do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/invalid JSON report shape/, findings.first.message)
    end
  end

  def test_empty_rubocop_file_array_is_not_clean
    with_rubocop_report(stdout: JSON.generate("files" => [])) do |rule|
      findings = rule.check("def sample; end\n", path: "sample.rb")

      assert_equal 1, findings.size
      assert_match(/invalid JSON report shape/, findings.first.message)
    end
  end

  def test_reek_rejects_a_valid_json_value_that_is_not_a_report_array
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { ['{"issues":[]}', "", status] }) do
          findings = rule.check("def sample; end\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_match(/invalid JSON report shape/, findings.first.message)
        end
      end
    end
  end

  def test_reek_rejects_array_entries_missing_the_fields_it_consumes
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { ['[{}]', "", status] }) do
          findings = rule.check("def sample; end\\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_match(/scan error/, findings.first.message)
          assert_match(/invalid JSON report shape/, findings.first.message)
        end
      end
    end
  end

  def test_reek_rejects_non_positive_or_non_integer_line_numbers
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    report = JSON.generate([{ "smell_type" => "Example", "message" => "example", "lines" => [0, "2"] }])
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { [report, "", status] }) do
          findings = rule.check("def sample; end\\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_match(/invalid JSON report shape/, findings.first.message)
        end
      end
    end
  end

  def test_reek_valid_smell_record_preserves_all_reported_lines
    status = Struct.new(:exitstatus).new(2)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    report = JSON.generate([{
      "smell_type" => "Example",
      "message" => "example smell",
      "lines" => [2, 4]
    }])
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { [report, "", status] }) do
          findings = rule.check("def sample; end\\n", path: "sample.rb")

          assert_equal [2, 4], findings.map(&:line)
          assert findings.all? { |finding| finding.message.include?("Example") && finding.message.include?("example smell") }
        end
      end
    end
  end

  def test_reek_record_with_empty_lines_still_surfaces_the_smell
    status = Struct.new(:exitstatus).new(0)
    rule = Master::Review::Scan::Laws::ReekLaw.new(root: Master::ROOT)
    report = JSON.generate([{ "smell_type" => "Example", "message" => "example", "lines" => [] }])
    rule.stub(:linter_available?, true) do
      Operator::RubyRunner.stub(:bundle_cmd, "bundle") do
        Master::Io::Exec.stub(:capture3, ->(*_args, **_options) { [report, "", status] }) do
          findings = rule.check("def sample; end\\n", path: "sample.rb")

          assert_equal 1, findings.size
          assert_equal 1, findings.first.line
          assert_match(/Example/, findings.first.message)
        end
      end
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
