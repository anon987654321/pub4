# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeJit < Minitest::Test
  def test_mode_defaults_to_auto
    ENV.delete("MASTER_JIT")
    assert_equal "auto", Master::Runtime::Jit.mode
  end

  def test_invalid_mode_falls_back_to_auto
    previous = ENV["MASTER_JIT"]
    ENV["MASTER_JIT"] = "banana"
    assert_equal "auto", Master::Runtime::Jit.mode
  ensure
    previous ? ENV["MASTER_JIT"] = previous : ENV.delete("MASTER_JIT")
  end

  def test_off_does_not_enable
    Master::Runtime::Jit.stub(:available?, true) do
      Master::Runtime::Jit.stub(:enabled?, false) do
        ENV["MASTER_JIT"] = "off"
        refute Master::Runtime::Jit.apply!
      end
    end
  ensure
    ENV.delete("MASTER_JIT")
  end

  def test_snapshot_has_stable_shape
    snapshot = Master::Runtime::Jit.snapshot
    assert snapshot.key?(:mode)
    assert snapshot.key?(:available)
    assert snapshot.key?(:enabled)
    assert snapshot.key?(:constrained)
    assert snapshot.key?(:stats)
  end
end
