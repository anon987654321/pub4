# frozen_string_literal: true

require_relative "test_helper"

class TestScriptDispatch < Minitest::Test
  def test_finds_master_tool_when_operating_from_workspace_root
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "repo_inventory")

    assert_equal Master.tool_path("repo_inventory.rb"), path
  end

  def test_uses_workspace_as_working_directory_for_fallback_tool
    workspace = File.expand_path("../..", __dir__)
    script = Master::Io::ScriptDispatch.script_path(workspace, "repo_inventory")

    assert_equal workspace, Master::Io::ScriptDispatch.working_directory(workspace, script)
  end

  def test_finds_media_tool_moved_out_to_studio
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "repligen")

    assert_equal File.join(MasterPaths.repo, "studio", "repligen", "repligen.rb"), path
  end

  def test_uses_own_directory_as_working_directory_for_studio_tool
    workspace = File.expand_path("../..", __dir__)
    script = Master::Io::ScriptDispatch.script_path(workspace, "repligen")

    assert_equal File.join(MasterPaths.repo, "studio", "repligen"), Master::Io::ScriptDispatch.working_directory(workspace, script)
  end
end
