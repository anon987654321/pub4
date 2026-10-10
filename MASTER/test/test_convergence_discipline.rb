# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/convergence_discipline"

class TestConvergenceDiscipline < Minitest::Test
  def setup
    @root = Dir.mktmpdir("convergence_discipline")
    @bus = Struct.new(:events) do
      def publish(event, payload = {})
        events << [event, payload]
      end
    end.new([])
    @path = File.join(@root, "example.rb")
    File.write(@path, "puts :ok\n")
    @discipline = Master::Fix::ConvergenceDiscipline.new(root: @root, bus: @bus)
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def test_begin_run_records_read_evidence_and_observe_tracks_best_state
    baseline = @discipline.begin_run([@path])
    refute_empty baseline
    @discipline.observe(pass: 1, findings: [{ rule: "A" }], files: [@path], progressed: true)
    @discipline.observe(pass: 2, findings: [], files: [@path], progressed: true)

    assert_equal 0, @discipline.best_state.fetch(:score)
    assert_equal 2, @discipline.best_state.fetch(:pass)
    assert @bus.events.any? { |event, _| event == "fix_loop:convergence_measure" }
  end

  def test_observe_emits_attention_budget
    @discipline.begin_run([@path])
    @discipline.observe(pass: 1, findings: [
      { rule: "high", consumers: 8, confidence: 0.9 },
      { rule: "uncertain", confidence: 0.1, status: :uncertain },
    ], files: [@path], progressed: false)

    event = @bus.events.find { |name, _| name == "fix_loop:attention" }
    refute_nil event
    assert_equal 2, event.last.fetch(:candidates)
    assert_equal true, event.last.fetch(:preserved_uncertainty)
  end

  def test_finding_digest_is_order_independent_and_risk_ordering_is_lexicographic
    @discipline.begin_run([@path])
    findings = [
      { law: "ROBUSTNESS", file: "example.rb", line: 2, message: "unsafe input", severity: :error },
      { law: "DENSITY", file: "example.rb", line: 4, message: "long method", severity: :warning },
    ]
    first = @discipline.observe(pass: 1, findings:, files: [@path], progressed: false)
    second = @discipline.observe(pass: 2, findings: findings.reverse, files: [@path], progressed: false)

    assert_equal first[:finding_digest], second[:finding_digest]
    refute @discipline.improving?

    third = @discipline.observe(
      pass: 3,
      findings: [{ law: "DENSITY", file: "example.rb", line: 4, message: "long method", severity: :warning }],
      files: [@path],
      progressed: false,
    )
    assert_equal [0, 0, 1, 0], third[:risk_vector]
    assert @discipline.improving?
    assert_equal third[:finding_digest], @discipline.receipt.fetch(:finding_digest)
  end

  def test_adaptive_decision_requires_progress_and_respects_hard_limits
    assert_equal :no_improvement,
                 @discipline.adaptive_decision(deadline_expired: false, pass_limit: 1, absolute_limit: 60).reason

    @discipline.begin_run([@path])
    @discipline.observe(pass: 1, findings: [], files: [@path], progressed: true)
    assert_equal :extend,
                 @discipline.adaptive_decision(deadline_expired: false, pass_limit: 1, absolute_limit: 60).action
    assert_equal :deadline,
                 @discipline.adaptive_decision(deadline_expired: true, pass_limit: 1, absolute_limit: 60).reason
    assert_equal :absolute_limit,
                 @discipline.adaptive_decision(deadline_expired: false, pass_limit: 60, absolute_limit: 60).reason
  end

  def test_finding_fingerprint_survives_source_line_movement
    first = { law: "ROBUSTNESS", file: "example.rb", line: 8, fingerprint: "unsafe-call:abc123" }
    moved = { law: "ROBUSTNESS", file: "example.rb", line: 19, fingerprint: "unsafe-call:abc123" }

    assert_equal @discipline.send(:finding_identity, first), @discipline.send(:finding_identity, moved)
  end

  def test_clean_proof_rejects_governing_authority_drift
    authority = File.join(@root, "authority.yml")
    File.write(authority, "authority: original\\n")
    @discipline.define_singleton_method(:authority_paths) { [authority] }
    @discipline.begin_run([@path])
    File.write(authority, "authority: changed\\n")

    proof = @discipline.clean_proof(files: [@path], pass: 2, clean_runs: 2)

    refute proof.fetch(:eligible)
    assert proof.fetch(:fatal)
    assert_match(/governing authority changed/, proof.fetch(:reason))
  end

  def test_clean_proof_refuses_unreadable_files
    missing = File.join(@root, "missing.rb")
    @discipline.begin_run([@path, missing])

    proof = @discipline.clean_proof(files: [@path, missing], pass: 2, clean_runs: 2)

    refute proof.fetch(:eligible)
    assert proof.fetch(:fatal)
    assert_equal "files unread", proof.fetch(:reason)
  end

  def test_clean_proof_requires_the_historical_clean_streak
    @discipline.begin_run([@path])

    proof = @discipline.clean_proof(files: [@path], pass: 1, clean_runs: 1)

    refute proof.fetch(:eligible)
    refute proof.fetch(:fatal)
  end

  def test_clean_proof_is_evidence_backed
    @discipline.begin_run([@path])

    proof = @discipline.clean_proof(files: [@path], pass: 2, clean_runs: 2)

    assert proof.fetch(:eligible)
    assert_equal 1, proof.fetch(:files_verified)
  end

  def test_strategy_rotates_with_risk_size_and_language_diversity
    assert_equal :consensus, @discipline.strategy_for(files: [@path], findings: [])
    assert_equal :adversarial,
                 @discipline.strategy_for(files: [@path], findings: [{ rule: "SQL_INJECTION" }])
    many = Array.new(8, @path)
    assert_equal :ensemble, @discipline.strategy_for(files: many, findings: [])
    assert_equal :incremental,
                 @discipline.strategy_for(files: [@path], findings: Array.new(8) { { rule: "STYLE" } })
  end

  def test_reasoning_contract_restores_cognitive_and_scientific_method_constraints
    text = @discipline.reasoning_contract(strategy: :adversarial, files: [@path], findings: [])

    assert_includes text, "scientific method"
    assert_includes text, "active-file budget"
    assert_includes text, "independent-concern budget"
    assert_includes text, "alternatives"
    assert_includes text, "simulated"
  end
end
