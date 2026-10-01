<sub># frozen_string_literal: true

require_relative "test_helper"
require "fileutils"
require "tmpdir"

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

  def test_finds_media_tool_under_master_tools
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "replicate")

    assert_equal File.join(MasterPaths.repo, "MASTER", "tools", "replicate", "replicate.rb"), path
  end

  def test_uses_own_directory_as_working_directory_for_master_tool
    workspace = File.expand_path("../..", __dir__)
    script = Master::Io::ScriptDispatch.script_path(workspace, "replicate")

    assert_equal File.join(MasterPaths.repo, "MASTER", "tools", "replicate"), Master::Io::ScriptDispatch.working_directory(workspace, script)
  end

  # Regression test: dilla is the one media tool where MASTER/tools/dilla/ also
  # contains an unrelated archived file (archive/hiphop_techno_experiment.rb)
  # that used to sit at the old STUDIO/dilla/dilla.rb path and silently hijack this exact
  # resolution path (MediaIntent's chat-driven beat requests resolved to it
  # instead of the real engine, with no test catching it).
  def test_finds_dilla_engine_under_master_tools
    workspace = File.expand_path("../..", __dir__)
    path = Master::Io::ScriptDispatch.script_path(workspace, "dilla")

    assert_equal File.join(MasterPaths.repo, "MASTER", "tools", "dilla", "dilla.rb"), path
    assert File.file?(path)
  end

  def test_tool_child_inherits_master_bundle_environment
    Dir.mktmpdir("master-tool-dispatch") do |root|
      tool_dir = File.join(root, "tools", "probe")
      FileUtils.mkdir_p(tool_dir)
      script = File.join(tool_dir, "probe.rb")
      File.write(script, <<~'RUBY')
        puts [ENV["BUNDLE_GEMFILE"], ENV["BUNDLE_PATH"], ENV["GEM_HOME"], ENV["RUBYOPT"]].map(&:inspect).join(" ")
      RUBY

      previous = ENV.to_h.select { |key, _| key.start_with?("BUNDLE_") || %w[GEM_HOME GEM_PATH RUBYOPT].include?(key) }
      begin
        ENV["BUNDLE_GEMFILE"] = File.join(root, "Gemfile")
        ENV["BUNDLE_PATH"] = File.join(root, "bundle")
        ENV["GEM_HOME"] = File.join(root, "gems")
        ENV["GEM_PATH"] = File.join(root, "gems")
        ENV["RUBYOPT"] = ""

        result = Master::Io::ScriptDispatch.run(root:, tool: "probe")

        assert result.ok?, -> { result.message.to_s }
        assert_equal %Q{"#{ENV["BUNDLE_GEMFILE"]}" "#{ENV["BUNDLE_PATH"]}" "#{ENV["GEM_HOME"]}" ""}, result.value!
      ensure
        ENV.keys.grep(/A(?:BUNDLE_|GEM_HOME|GEM_PATH|RUBYOPT)$/).each { |key| ENV.delete(key) }
        previous.each { |key, value| ENV[key] = value }
      end
    end
  end
end


</sub>