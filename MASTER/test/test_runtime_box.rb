# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeBox < Minitest::Test
  def test_snapshot_has_stable_shape
    snapshot = Master::Runtime::Box.snapshot

    %i[present enabled available startup_required startup_env current].each do |key|
      assert snapshot.key?(key)
    end
  end

  def test_box_capability_is_truthful
    if defined?(::Ruby::Box) && ::Ruby::Box.respond_to?(:enabled?)
      assert_equal ::Ruby::Box.enabled?, Master::Runtime::Box.enabled?
    else
      refute Master::Runtime::Box.enabled?
    end
  end

  def test_box_requires_startup_enablement
    return if Master::Runtime::Box.available?

    error = assert_raises(Master::Runtime::Box::Unavailable) do
      Master::Runtime::Box.new_box
    end
    assert_match(/Ruby::Box/, error.message)
  end

  def test_box_evaluation_preserves_explicit_box_requirement
    return if Master::Runtime::Box.available?

    assert_raises(Master::Runtime::Box::Unavailable) do
      Master::Runtime::Box.evaluate("1 + 1")
    end
  end

  def test_runtime_source_exposes_isolation_operations
    source = File.read(File.expand_path("../lib/runtime/box.rb", __dir__))

    assert_includes source, "::Ruby::Box.new"
    assert_includes source, "box.eval"
    assert_includes source, "box.load"
    assert_includes source, "RUBY_BOX"
  end
end
