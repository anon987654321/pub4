# frozen_string_literal: true

require "open3"
require "rbconfig"
require_relative "test_helper"

class TestResetCosts < Minitest::Test
  SCRIPT = File.join(Master::ROOT, "bin", "reset-costs")

  def test_dry_run_preserves_state
    with_state do |root, cost_path|
      _out, _err, status = Open3.capture3(RbConfig.ruby, SCRIPT, "--root", root, "--dry-run")
      assert status.success?
      assert_equal "one\n", File.read(cost_path)
    end
  end

  def test_yes_archives_then_resets
    with_state do |root, cost_path|
      out, err, status = Open3.capture3(RbConfig.ruby, SCRIPT, "--root", root, "--yes")
      assert status.success?, err
      assert_empty File.read(cost_path)
      archives = Dir.glob(File.join(root, ".master", "archives", "*", "costs.jsonl"))
      assert_equal 1, archives.size
      assert_equal "one\n", File.read(archives.first)
      assert_match(/archived/, out)
    end
  end

  private

  def with_state
    Dir.mktmpdir do |root|
      state = File.join(root, ".master")
      FileUtils.mkdir_p(state)
      cost_path = File.join(state, "costs.jsonl")
      File.write(cost_path, "one\n")
      yield root, cost_path
    end
  end
end
