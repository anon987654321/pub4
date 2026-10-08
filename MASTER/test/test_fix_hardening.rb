# frozen_string_literal: true

require "set"
require_relative "test_helper"

class FixHardeningTest < Minitest::Test
  RuleStub = Data.define(:id, :severity) do
    def scannable? = true
    def semantic? = false
    def practice = nil
  end

  def test_measurement_only_policy_is_law_backed
    ids = Master::Review::Scan::LawHealth.measurement_only_ids

    assert_includes ids, "CQS"
    assert_includes ids, "MAGIC_COLOR"
    assert_includes ids, "DOUBLE_QUOTES_RUBY"
  end

  def test_measurement_only_finding_stays_visible_but_becomes_non_actionable
    finding = {
      rule: "MAGIC_COLOR",
      severity: :warning,
      tags: [:DESIGN],
      line: 12,
      message: "raw hex color",
    }

    annotated = Master::Review::Scan::LawHealth.annotate(finding)

    assert_equal :warning, annotated[:original_severity]
    assert_equal :info, annotated[:severity]
    assert_equal "measurement", annotated[:enforcement]
    assert_includes annotated[:tags], :MEASUREMENT_ONLY
  end

  def test_detector_matrix_serializes_path_exclusion_regexes
    rule = Data.define(:id, :severity, :path_exclude).new(
      "REGEX_RULE", :warning, %r{/generated/\.rb\z}
    )

    matrix = Master::Fix::ProtocolDetectorMatrix.matrix([rule])

    assert_equal ["/generated/\\.rb\\z"], matrix.fetch("REGEX_RULE").fetch("path_exclude")
    assert JSON.parse(JSON.generate(matrix)).fetch("REGEX_RULE")
  end

  def test_detector_matrix_reports_enforcement_and_summary
    rules = [
      RuleStub.new(id: "MAGIC_COLOR", severity: :warning),
      RuleStub.new(id: "ROBUSTNESS", severity: :error),
    ]

    matrix = Master::Fix::ProtocolDetectorMatrix.matrix(rules)

    assert_equal "measurement", matrix.fetch("MAGIC_COLOR").fetch("enforcement")
    assert_equal true, matrix.fetch("MAGIC_COLOR").fetch("measurement_mode")
    assert_equal "blocking", matrix.fetch("ROBUSTNESS").fetch("enforcement")
    assert_equal 2, Master::Fix::ProtocolDetectorMatrix.summary(matrix).fetch("total_rules")
  end

  def test_measurement_only_finding_is_not_repaired_in_law_loop
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\\n")
      scanner = Object.new
      scanner.define_singleton_method(:scan) do |_path, rules: nil|
        Master::Result.ok([{ rule: "CQS", severity: :warning, line: 1, message: "measured" }])
      end
      agent = Object.new
      agent.define_singleton_method(:ask) { |_prompt| raise "measurement-only finding reached the model" }
      loop = Master::Fix::LawLoop.new(
        rule: RuleStub.new(id: "CQS", severity: :warning),
        agent:,
        scanner:,
        root:,
      )

      result = loop.run_once([path])

      assert_equal :clean, result[:status]
      assert_equal "puts :x\\n", File.read(path)
    end
  end

  def test_rendered_value_block_is_a_human_decision
    loop = Master::Fix::LawLoop.allocate
    finding = {
      rule: "TYPE_SCALE",
      file: File.join(Master::ROOT, "web", "face.css"),
      line: 1,
      severity: :warning,
      message: "type scale",
    }

    outcome = loop.send(:fix_violation, finding)

    assert_equal :needs_person, outcome
    assert_equal :human_decision, loop.send(:pass_outcome, 0)
  end

  def test_stream_refresh_replaces_stale_touched_findings
    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.define_singleton_method(:violations_for) do |path|
      [{ rule: "FRESH", file: path, line: 2 }]
    end
    runner.define_singleton_method(:resolve_violations) do |rows|
      rows
    end
    runner.instance_variable_set(:@root, Master::ROOT)

    found = [
      { rule: "STALE", file: "lib/master.rb", line: 1 },
      { rule: "UNTOUCHED", file: "lib/other.rb", line: 4 },
    ]
    streamed = Set.new([["lib/master.rb", "STALE"]])

    refreshed = runner.send(:refresh_streamed_findings, found, streamed)

    assert_equal %w[UNTOUCHED FRESH], refreshed.map { |row| row[:rule] }
    refute refreshed.any? { |row| row[:rule] == "STALE" }
  end
end
