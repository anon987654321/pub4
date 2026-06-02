# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestConstitution < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("constitution_test")
    Master::Ground::Constitution.clear_cache!
  end

  def teardown
    FileUtils.remove_entry(@dir)
    Master::Ground::Constitution.clear_cache!
  end

  def test_instances_share_cached_snapshot_until_reload
    write_principle("first")
    first = Master::Ground::Constitution.new(dir: @dir)
    write_principle("second")
    second = Master::Ground::Constitution.new(dir: @dir)

    assert_includes first.system_prompt, "first"
    assert_includes second.system_prompt, "first"
    refute_includes second.system_prompt, "second"
  end

  def test_reload_invalidates_cache_for_directory
    write_principle("first")
    constitution = Master::Ground::Constitution.new(dir: @dir)
    write_principle("second")

    constitution.reload!

    assert_includes constitution.system_prompt, "second"
  end

  private

  def write_principle(body)
    File.write(File.join(@dir, "principle.md"), <<~MD)
      ---
      name: Test
      description: Cache test
      type: axiom
      ---
      #{body}
    MD
  end
end
