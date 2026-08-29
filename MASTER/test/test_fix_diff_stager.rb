# frozen_string_literal: true

require_relative "test_helper"

class TestDiffStager < Minitest::Test
  def setup
    @root = Dir.mktmpdir("diff_stager")
    @target = File.join(@root, "sample.txt")
    File.write(@target, "before\n")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_reload_pending_restores_content_after_restart
    stager = Master::Fix::DiffStager.new(root: @root)
    result = stager.stage(path: @target, new_content: "after\n", tool: "WriteFile")
    assert result.ok?
    id = result.value![:id]

    reloaded = Master::Fix::DiffStager.new(root: @root)
    assert_equal 1, reloaded.size
    entry = reloaded.pending.first
    assert_equal id, entry.id
    assert_equal "before\n", entry.old_content
    assert_equal "after\n", entry.new_content
  end

  def test_apply_removes_persisted_sidecars
    stager = Master::Fix::DiffStager.new(root: @root)
    stager.stage(path: @target, new_content: "applied\n", tool: "WriteFile")
    stager.apply
    assert_equal "applied\n", File.read(@target)
    assert_empty Dir.glob(File.join(@root, ".master", "pending", "*"))
  end
end
