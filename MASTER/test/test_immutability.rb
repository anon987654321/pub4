# frozen_string_literal: true

require_relative "test_helper"

class TestImmutability < Minitest::Test
  def test_blocked_follows_the_declared_sacred_paths
    with_fixture do |root|
      checker = Master::Ground::Immutability.new(root:)
      assert checker.blocked?(File.join(root, "data", "future.yml"))
      assert checker.blocked?("SOUL.md")
      refute checker.blocked?(File.join(root, "lib", "future.rb"))
    end
  end

  def test_a_path_escaping_the_root_is_blocked
    with_fixture do |root|
      assert Master::Ground::Immutability.new(root:).blocked?("../outside.rb")
    end
  end

  def test_an_empty_sacred_manifest_fails_closed
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(File.join(root, "data", "soul.yml"), "absolute:\n  sacred_paths: []\n")
      assert_raises(Master::Ground::Immutability::Violation) do
        Master::Ground::Immutability.new(root:).blocked?("lib/x.rb")
      end
    end
  end

  # The live manifest names the law catalogue and the soul itself: automation may not write either.
  def test_the_live_manifest_blocks_the_laws_and_the_soul
    assert Master::Ground::Immutability.blocked?("data/laws.yml")
    assert Master::Ground::Immutability.blocked?("data/soul.yml")
    refute Master::Ground::Immutability.blocked?("data/tokens.yml")
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
