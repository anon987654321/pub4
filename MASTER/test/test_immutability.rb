# frozen_string_literal: true

require_relative "test_helper"

class TestImmutability < Minitest::Test
  def test_regen_then_verify_is_stable_across_multiple_regenerations
    with_fixture do |root|
      checker = Master::Ground::Immutability.new(root:)
      assert checker.regen!.ok?
      assert_equal :clean, checker.verify!.value!
      assert checker.regen!.ok?
      assert_equal :clean, checker.verify!.value!
    end
  end

  def test_drift_raises_violation
    with_fixture do |root|
      checker = Master::Ground::Immutability.new(root:)
      checker.regen!
      File.write(File.join(root, "data", "soul.yml"), "absolute:\n  sacred_paths: []\n")

      assert_raises(Master::Ground::Immutability::Violation) { checker.verify! }
    end
  end

  def test_new_file_under_sacred_directory_is_drift
    with_fixture do |root|
      checker = Master::Ground::Immutability.new(root:)
      checker.regen!
      File.write(File.join(root, "data", "new.yml"), "new: true\n")

      assert_raises(Master::Ground::Immutability::Violation) { checker.verify! }
    end
  end

  def test_blocked_uses_declarations_even_without_checksum_store
    with_fixture do |root|
      checker = Master::Ground::Immutability.new(root:)
      assert checker.blocked?(File.join(root, "data", "future.yml"))
      refute checker.blocked?(File.join(root, "lib", "future.rb"))
    end
  end

  def test_missing_checksums_is_explicit
    with_fixture do |root|
      result = Master::Ground::Immutability.new(root:).verify!
      assert_equal :no_checksums, result.value!
    end
  end

  private

  def with_fixture
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "soul.yml"), "absolute:\n  sacred_paths:\n    - data/\n    - SOUL.md\n")
      File.write(File.join(root, "SOUL.md"), "# soul\n")
      yield root
    end
  end
end
