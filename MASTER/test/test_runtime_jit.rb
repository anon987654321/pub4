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

  def test_zjit_is_an_explicit_opt_in_mode
    assert_includes Master::Runtime::Jit::MODES, "zjit"
    Master::Runtime::Jit.stub(:enable_zjit!, ->(reason:) { reason == "forced" }) do
      ENV["MASTER_JIT"] = "zjit"
      assert Master::Runtime::Jit.apply!
    end
  ensure
    ENV.delete("MASTER_JIT")
  end

  def test_zjit_is_not_auto_selected
    Master::Runtime::Jit.stub(:auto_allowed?, true) do
      Master::Runtime::Jit.stub(:enable_yjit!, ->(reason:) { reason == "auto" }) do
        ENV.delete("MASTER_JIT")
        assert Master::Runtime::Jit.apply!
      end
    end
  ensure
    ENV.delete("MASTER_JIT")
  end

  def test_snapshot_has_stable_shape
    snapshot = Master::Runtime::Jit.snapshot
    %i[mode available enabled constrained yjit_available yjit_enabled zjit_available zjit_enabled stats].each do |key|
      assert snapshot.key?(key)
    end
  end
end
