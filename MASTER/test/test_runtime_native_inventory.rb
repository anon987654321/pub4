# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeNativeInventory < Minitest::Test
  FakeSpec = Struct.new(:name, :version, :extensions, :metadata)

  def test_native_requires_declared_extensions
    native = FakeSpec.new("native_gem", "1.0.0", ["ext/native/extconf.rb"], {})
    assert Master::Runtime::NativeInventory.native?(native)
  end

  def test_ractor_safety_defaults_to_unknown
    spec = FakeSpec.new("native_gem", "1.0.0", ["ext/native/extconf.rb"], {})
    assert_equal "unknown", Master::Runtime::NativeInventory.ractor_safety(spec)
  end

  def test_explicit_ractor_metadata_is_respected
    safe = FakeSpec.new("safe_gem", "1.0.0", ["ext/native/extconf.rb"], { "ractor_safe" => "true" })
    unsafe = FakeSpec.new("unsafe_gem", "1.0.0", ["ext/native/extconf.rb"], { "ractor_safe" => "false" })

    assert_equal "safe", Master::Runtime::NativeInventory.ractor_safety(safe)
    assert_equal "unsafe", Master::Runtime::NativeInventory.ractor_safety(unsafe)
  end
end
