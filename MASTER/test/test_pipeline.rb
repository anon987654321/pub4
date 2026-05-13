# frozen_string_literal: true

require_relative "test_helper"

# Pipeline unit tests — Result-monadic chaining and rollback contract.
class TestPipeline < Minitest::Test
  include Master

  class OkStage
    def call(ctx) = Master::Result.ok(ctx.merge(stamped: true))
  end

  class ErrStage
    def initialize(cat = :unknown) = (@cat = cat)
    def call(_ctx) = Master::Result.err("boom", category: @cat)
  end

  class RaiseStage
    def call(_ctx) = raise "stage exploded"
  end

  def test_happy_path_passes_context_through
    pipe = Master::Now::Pipeline.new([OkStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok(input: "hi"))
    assert result.ok?
    assert result.value![:stamped]
  end

  def test_first_error_short_circuits
    pipe = Master::Now::Pipeline.new([OkStage.new, ErrStage.new, OkStage.new])
    result = pipe.call(Master::Result.ok({}))
    refute result.ok?
    assert_equal "boom", result.message
  end

  def test_raise_in_stage_becomes_err
    pipe = Master::Now::Pipeline.new([OkStage.new, RaiseStage.new])
    result = pipe.call(Master::Result.ok({}))
    refute result.ok?
    assert_match(/exploded/, result.message)
  end

  def test_rollback_skipped_outside_git_workspace
    # In /tmp (no .git), rollback is a no-op — must not crash.
    Dir.mktmpdir do |dir|
      pipe = Master::Now::Pipeline.new([ErrStage.new(:validation)], root: dir)
      result = pipe.call(Master::Result.ok({}))
      refute result.ok?
      # No exception raised = success for this test.
    end
  end
end
