# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/ai"
require "tmpdir"
require "fileutils"

class TestAiOrientation < Minitest::Test
  def setup
    @root = Dir.mktmpdir("orientation_")
    @master = File.join(@root, "MASTER")
    FileUtils.mkdir_p(File.join(@master, "lib", "io"))
    FileUtils.mkdir_p(File.join(@master, "runtime"))
    File.write(File.join(@root, "CLAUDE.md"), "authority order\n")
    File.write(File.join(@root, "TREE.md"), "TREE\n")
    File.write(File.join(@root, "TODO.md"), "TODO\n")
    File.write(File.join(@master, "lib", "master.rb"), "module Master\nend\n")
    File.write(File.join(@master, "runtime", "active_plan.md"), "repair boot\nverify again\n")
    File.write(File.join(@master, "runtime", "wishlist.md"), "# MASTER wishlist\n\n### 1. Better boot receipt\n\n")
  end

  def teardown = FileUtils.rm_rf(@root)

  def test_render_is_compact_live_context_and_includes_pending_work
    text = Master::AI::Orientation.render(root: @master, target: File.join(@master, "lib"))

    assert_includes text, "MASTER orientation v1"
    assert_includes text, "target: MASTER/lib"
    assert_includes text, "active plan: repair boot verify again"
    assert_includes text, "pending wishes: 1. Better boot receipt"
    assert_includes text, "lib/"
    assert_includes text, "io/"
    assert_includes text, "master.rb"
    refute_includes text, ".master"
  end

  def test_digest_is_stable_for_the_same_observation
    first = Master::AI::Orientation.digest(root: @master)
    second = Master::AI::Orientation.digest(root: @master)

    assert_equal first, second
    assert_match(/\A[0-9a-f]{16}\z/, first)
  end
end
