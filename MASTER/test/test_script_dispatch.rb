# frozen_string_literal: true

require_relative "test_helper"

class TestScriptDispatch < Minitest::Test
  def test_finds_master_tool_when_operating_from_workspace_root
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "repo_inventory")

    assert_equal File.join(Master::ROOT, "tools", "repo_inventory.rb"), path
  end

  def test_uses_workspace_as_working_directory_for_fallback_tool
    workspace = File.expand_path("../..", __dir__)
    script = Master::Io::ScriptDispatch.script_path(workspace, "repo_inventory")

    assert_equal workspace, Master::Io::ScriptDispatch.working_directory(workspace, script)
  end

  def test_finds_media_tool_under_studio
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "replicate")

    assert_equal File.join(MasterPaths.repo, "STUDIO", "replicate", "replicate.rb"), path
  end

  def test_uses_own_directory_as_working_directory_for_studio_tool
    workspace = File.expand_path("../..", __dir__)
    script = Master::Io::ScriptDispatch.script_path(workspace, "replicate")

    assert_equal File.join(MasterPaths.repo, "STUDIO", "replicate"), Master::Io::ScriptDispatch.working_directory(workspace, script)
  end

  def test_media_compatibility_link_still_resolves
    workspace = File.expand_path("../..", __dir__)
    path = File.join(MasterPaths.repo, "MASTER", "tools", "dilla", "dilla.rb")

    assert File.file?(path), "the MASTER/tools compatibility link must remain usable"
    assert_equal File.join(MasterPaths.repo, "STUDIO", "dilla", "dilla.rb"),
                 Master::Io::ScriptDispatch.script_path(workspace, "dilla")
  end

  # The canonical path is a real file; MASTER/tools is only the compatibility
  # surface. A dispatcher must not accidentally make the link the source of truth.
  def test_finds_dilla_engine_under_studio
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "dilla")

    assert_equal File.join(MasterPaths.repo, "MASTER", "tools", "dilla", "dilla.rb"), path
    assert File.file?(path)
  end
end
