# frozen_string_literal: true

require_relative "test_helper"

# Pipeline unit tests — Result-monadic chaining and rollback contract.
class TestPipeline < Minitest::Test
  include Master

  class OkStage
    def call(ctx) = Master::Result.ok(ctx.merge(output: "ok"))
  end

  class ErrStage
    def initialize(cat = :unknown) = (@cat = cat)
    def call(_ctx) = Master::Result.err("boom", category: @cat)
  end

  class RaiseStage
    def call(_ctx) = raise "stage exploded"
  end

  FakeRule = Struct.new(:id, :auto_fix)

  class FakeScanner
    attr_reader :rules

    def initialize(findings)
      @findings = findings
      @rules = [FakeRule.new("SELF_RULE", false)]
    end

    def scan_dir(path, depth:, stream: false)
      Master::Result.ok([[File.join(path, "example.rb"), Master::Result.ok(@findings)]])
    end
  end

  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  def test_happy_path_passes_context_through
    pipe = Master::Now::Pipeline.new([OkStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    assert result.ok?
    assert_equal "ok", result.value![:output]
  end

  def test_first_error_short_circuits
    pipe = Master::Now::Pipeline.new([OkStage.new, ErrStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    refute result.ok?
    assert_equal "boom", result.message
  end

  def test_raise_in_stage_becomes_err
    pipe = Master::Now::Pipeline.new([OkStage.new, RaiseStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    refute result.ok?
    assert_match(/exploded/, result.message)
  end

  def test_rollback_skipped_outside_git_workspace
    # In /tmp (no .git), rollback is a no-op — must not crash.
    Dir.mktmpdir do |dir|
      pipe = Master::Now::Pipeline.new([ErrStage.new(:validation)], root: dir)
      result = pipe.call(Master::Result.ok(user_message: "hi"))
      refute result.ok?
      # No exception raised = success for this test.
    end
  end

  def test_deploy_gate_blocks_when_self_scan_has_violations
    Dir.mktmpdir do |dir|
      write_rules(dir)
      bus = FakeBus.new
      scanner = FakeScanner.new([{ rule: "SELF_RULE", line: 1, message: "violation" }])
      pipe = Master::Now::Pipeline.new([OkStage.new], root: dir, scanner:, bus:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/deploy blocked/, result.message)
      assert_includes bus.events.map(&:first), "pipeline:blocked"
    end
  end

  def test_deploy_gate_blocks_when_evidence_score_is_too_low
    Dir.mktmpdir do |dir|
      write_rules(dir)
      scanner = FakeScanner.new([])
      pipe = Master::Now::Pipeline.new([OkStage.new], root: dir, scanner:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/evidence score 25 below 80/, result.message)
    end
  end

  def test_deploy_gate_passes_with_enough_evidence
    Dir.mktmpdir do |dir|
      write_rules(dir)
      scanner = FakeScanner.new([])
      pipe = Master::Now::Pipeline.new([OkStage.new], root: dir, scanner:)

      result = pipe.call(Master::Result.ok(
        user_message: "deploy now",
        metadata: { evidence: { test_pass: true, code_review: true } }
      ))

      assert result.ok?
      assert_equal "ok", result.value![:output]
    end
  end

  def test_deploy_gate_skips_non_deploy_messages
    Dir.mktmpdir do |dir|
      scanner = FakeScanner.new([{ rule: "SELF_RULE", line: 1, message: "violation" }])
      pipe = Master::Now::Pipeline.new([OkStage.new], root: dir, scanner:)

      result = pipe.call(Master::Result.ok(user_message: "scan the project"))

      assert result.ok?
      assert_equal "ok", result.value![:output]
    end
  end

  private

  def write_rules(root)
    FileUtils.mkdir_p(File.join(root, "data"))
    File.write(File.join(root, "data", "rules.yml"), <<~YAML)
      evidence_scoring:
        weights:
          test_pass: 35
          scan_clean: 25
          code_review: 20
        pass_threshold: 80
    YAML
  end
end
