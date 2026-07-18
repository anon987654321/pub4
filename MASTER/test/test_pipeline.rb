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

  class AddStage
    def initialize(key, value)
      @key = key
      @value = value
    end

    def call(ctx) = Master::Result.ok(ctx.merge(@key => @value))
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
    pipe = Master::CLI::Pipeline.new([OkStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    assert result.ok?
    assert_equal "ok", result.value![:output]
  end

  def test_call_accepts_already_wrapped_pipeline_context
    pipe = Master::CLI::Pipeline.new([OkStage.new])
    ctx = Master::CLI::PipelineContext.build(user_message: "hi")

    result = pipe.call(ctx)

    assert result.ok?
    assert_equal "ok", result.value![:output]
  end

  def test_pipeline_complete_event_publishes_timings
    bus = FakeBus.new
    pipe = Master::CLI::Pipeline.new([OkStage.new], bus:)

    result = pipe.call(Master::Result.ok(user_message: "hi"))

    assert result.ok?
    event = bus.events.find { |name, _payload| name == "pipeline:complete" }
    assert event
    assert_equal true, event.last[:success]
    assert_includes event.last[:timings].keys, "OkStage"
  end

  def test_pipeline_context_caps_large_output_on_merge
    ctx = Master::CLI::PipelineContext.build(user_message: "hi")
    merged = ctx.merge(output: "x" * 10_000)

    assert_equal Master::CLI::PipelineContext::MAX_OUTPUT_BYTES, merged[:output].bytesize
  end

  def test_pipeline_context_caps_timing_entries_on_merge
    ctx = Master::CLI::PipelineContext.build(user_message: "hi")
    timings = 25.times.to_h { |i| ["stage#{i}", i] }
    merged = ctx.merge(_timings: timings)

    assert_equal Master::CLI::PipelineContext::MAX_TIMINGS, merged[:_timings].size
    refute_includes merged[:_timings].keys, "stage0"
    assert_includes merged[:_timings].keys, "stage24"
  end

  def test_first_error_short_circuits
    pipe = Master::CLI::Pipeline.new([OkStage.new, ErrStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    refute result.ok?
    assert_equal "boom", result.message
  end

  def test_raise_in_stage_becomes_err
    pipe = Master::CLI::Pipeline.new([OkStage.new, RaiseStage.new])
    result = pipe.call(Master::Result.ok(user_message: "hi"))
    refute result.ok?
    assert_match(/exploded/, result.message)
  end

  def test_rollback_skipped_outside_git_workspace
    # In /tmp (no .git), rollback is a no-op — must not crash.
    Dir.mktmpdir do |dir|
      pipe = Master::CLI::Pipeline.new([ErrStage.new(:validation)], root: dir)
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
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:, bus:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/deploy blocked/, result.message)
      assert_includes bus.events.map(&:first), "pipeline:blocked"
    end
  end

  def test_deploy_gate_blocks_tier1_critical_principles_first
    Dir.mktmpdir do |dir|
      write_rules(dir)
      bus = FakeBus.new
      scanner = FakeScanner.new([{ rule: "PRESERVE_FIRST", rule_id: "PRESERVE_FIRST", line: 1, message: "breaks behavior" }])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:, bus:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_equal :policy, result.category
      assert_match(/tier1 critical/, result.message)
      assert_equal "tier1_critical", bus.events.find { |event, _| event == "pipeline:blocked" }.last[:gate]
    end
  end

  def test_tier1_critical_deploy_block_rolls_back_dirty_workspace
    Dir.mktmpdir do |dir|
      init_git_repo(dir)
      write_rules(dir)
      FileUtils.mkdir_p(File.join(dir, "lib"))
      File.write(File.join(dir, "lib", "tracked.rb"), "puts :clean\n")
      system("git", "-C", dir, "add", ".")
      system("git", "-C", dir, "commit", "-m", "baseline", out: File::NULL, err: File::NULL)
      File.write(File.join(dir, "lib", "tracked.rb"), "puts :dirty\n")
      bus = FakeBus.new
      scanner = FakeScanner.new([{ rule: "PRESERVE_FIRST", rule_id: "PRESERVE_FIRST", line: 1, message: "breaks behavior" }])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:, bus:)

      result = pipe.call(Master::Result.ok(user_message: "deploy now"))

      refute result.ok?
      assert_includes bus.events.map(&:first), "pipeline:rollback"
      assert_equal "puts :clean\n", File.read(File.join(dir, "lib", "tracked.rb"))
    end
  end

  def test_deploy_gate_blocks_when_evidence_score_is_too_low
    Dir.mktmpdir do |dir|
      write_rules(dir)
      scanner = FakeScanner.new([])
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:)

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
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:)

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
      pipe = Master::CLI::Pipeline.new([OkStage.new], root: dir, scanner:)

      result = pipe.call(Master::Result.ok(user_message: "scan the project"))

      assert result.ok?
      assert_equal "ok", result.value![:output]
    end
  end

  def test_parallel_group_merges_successes_and_errors_in_one_pass
    group = Master::CLI::Pipeline::ParallelGroup.new(AddStage.new(:a, 1), ErrStage.new)

    result = group.call({ base: true })

    assert result.ok?
    assert_equal true, result.value![:base]
    assert_equal 1, result.value![:a]
    assert_equal ["boom"], result.value![:_parallel_errors]
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

  def init_git_repo(root)
    system("git", "-C", root, "init", "-q")
    system("git", "-C", root, "config", "user.email", "test@example.invalid")
    system("git", "-C", root, "config", "user.name", "Test")
  end
end
