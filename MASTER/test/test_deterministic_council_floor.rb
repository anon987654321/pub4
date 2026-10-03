# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/review/council/deterministic_floor"

class TestDeterministicCouncilFloor < Minitest::Test
  def test_valid_ruby_directory_passes_without_a_provider
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "ok.rb"), "# frozen_string_literal: true\nputs :ok\n")
      assert_equal 0, Master::Review::Council::DeterministicFloor.run(dir)
    end
  end

  def test_invalid_ruby_fails
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "bad.rb"), "def broken(\n")
      assert_equal 1, Master::Review::Council::DeterministicFloor.run(dir)
    end
  end

  def test_secret_shape_fails
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "leak.yml"), "token: r8_#{'a' * 24}\n")
      assert_equal 1, Master::Review::Council::DeterministicFloor.run(dir)
    end
  end

  def test_nonexistent_target_is_rejected
    error = assert_raises(ArgumentError) do
      Master::Review::Council::DeterministicFloor.run("does-not-exist")
    end
    assert_match(/does not exist/, error.message)
  end
end
