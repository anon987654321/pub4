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
      law: "MAGIC_COLOR",
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
    assert_equal 2, Master::Fix::ProtocolDetectorMatrix.summary(matrix).fetch("total_laws")
  end

  def test_measurement_only_finding_is_not_repaired_in_repair_loop
    Dir.mktmpdir do |root|
      path = File.join(root, "sample.rb")
      File.write(path, "puts :x\\n")
      scanner = Object.new
      scanner.define_singleton_method(:scan) do |_path, laws: nil|
        Master::Result.ok([{ law: "CQS", severity: :warning, line: 1, message: "measured" }])
      end
      agent = Object.new
      agent.define_singleton_method(:ask) { |_prompt| raise "measurement-only finding reached the model" }
      loop = Master::Fix::RepairLoop.new(
        law: RuleStub.new(id: "CQS", severity: :warning),
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
    loop = Master::Fix::RepairLoop.allocate
    finding = {
      law: "TYPE_SCALE",
      file: File.join(Master::ROOT, "..", "RAILS", "master", "face.css"),
      line: 1,
      severity: :warning,
      message: "type scale",
    }

    outcome = loop.send(:fix_violation, finding)

    assert_equal :needs_person, outcome
    assert_equal :human_decision, loop.send(:pass_outcome, 0)
  end

  def coverage_report(semantic_full:)
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) do |event, payload = nil, **keywords|
      events << [event, (payload || {}).merge(keywords)]
    end
    scan_phase = Object.new
    scan_phase.define_singleton_method(:semantic_full?) { semantic_full }

    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.instance_variable_set(:@scan_phase, scan_phase)
    runner.instance_variable_set(:@bus, bus)
    runner.send(
      :take_limits,
      clean_runs_required: 2,
      plateau_window: 3,
      ground_truth: nil,
      homeostat: nil,
      council: nil,
      visual_pass: nil,
      opportunity_pass: nil,
      discipline: Object.new,
      wishlist: nil,
    )
    capture_io { runner.instance_variable_get(:@coverage_reporter).call("MASTER", 1) }

    event = events.find { |name, _payload| name == "fix_loop:coverage" }
    refute_nil event
    event.last
  end

  def test_sampled_semantic_coverage_is_explicit_in_the_event_contract
    report = coverage_report(semantic_full: false)

    assert_equal "conditional/sampled", report.fetch(:semantic)
    assert_equal "conditional/sampled", report.fetch(:semantic_violations)
    assert_equal "conditional/sampled", report.fetch(:semantic_opportunities)
    assert_equal "contract_only_not_measurement", report.fetch(:assessment_matrix)
    assert_includes report.fetch(:lexical_violations), "not measured"
  end

  def test_full_semantic_mode_does_not_claim_the_surface_matrix_was_measured
    report = coverage_report(semantic_full: true)

    assert_equal "full", report.fetch(:semantic)
    assert_includes report.fetch(:semantic_violations), "surface matrix not measured"
    assert_includes report.fetch(:semantic_opportunities), "surface matrix not measured"
    assert_equal "contract_only_not_measurement", report.fetch(:assessment_matrix)
    assert_equal "not_measured", report.fetch(:assessment_matrix_status)
  end

  def test_clean_run_contract_has_a_two_pass_floor
    assert_operator Master::Fix::FixLoop::CLEAN_RUNS, :>=, 2
    assert_equal 2, Master::Fix::ConvergenceDiscipline::DEFAULTS.fetch("clean_runs_required")

    assert_equal 2, Master.config_section("convergence_discipline").fetch("clean_runs_required")
  end

  def test_clean_proof_uses_the_configured_clean_run_threshold
    captured = nil
    discipline = Object.new
    discipline.define_singleton_method(:clean_proof) do |**options|
      captured = options
      { eligible: false, fatal: false, reason: "clean streak incomplete" }
    end

    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.instance_variable_set(:@clean_runs_required, 4)
    runner.instance_variable_set(:@discipline, discipline)
    runner.instance_variable_set(:@ground_truth, nil)
    runner.instance_variable_set(:@bus, nil)
    runner.instance_variable_set(:@homeostat, nil)
    runner.define_singleton_method(:ground_truth_violations) { |_files| [] }
    runner.define_singleton_method(:quiescent?) { |_files, _mtimes| true }

    result = runner.send(:handle_clean_pass, ["example.rb"], {}, 3, 2)

    assert_equal 4, captured.fetch(:required_runs)
    assert_equal 3, captured.fetch(:clean_runs)
    assert_equal :continue, result.status
  end

  def test_stream_refresh_replaces_stale_touched_findings
    runner = Master::Fix::FixLoop::PassRunner.allocate
    runner.define_singleton_method(:violations_for) do |path|
      [{ law: "FRESH", file: path, line: 2 }]
    end
    runner.define_singleton_method(:resolve_violations) do |rows|
      rows
    end
    runner.instance_variable_set(:@root, Master::ROOT)

    found = [
      { law: "STALE", file: "lib/master.rb", line: 1 },
      { law: "UNTOUCHED", file: "lib/other.rb", line: 4 },
    ]
    streamed = Set.new([["lib/master.rb", "STALE"]])

    refreshed = runner.send(:refresh_streamed_findings, found, streamed)

    assert_equal %w[UNTOUCHED FRESH], refreshed.map { |row| row[:law] }
    refute refreshed.any? { |row| row[:law] == "STALE" }
  end
end
