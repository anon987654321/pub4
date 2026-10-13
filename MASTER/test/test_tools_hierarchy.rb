# frozen_string_literal: true

require_relative "test_helper"
require "yaml"

class TestToolsHierarchy < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  MASTER_ROOT = File.join(REPO_ROOT, "MASTER")
  TOOLS_ROOT = File.join(MASTER_ROOT, "tools")
  VOICE_TOOLS = %w[voice_benchmark.rb voice_measure.rb voice_quality.rb].freeze

  def test_voice_implementations_live_in_their_canonical_family
    VOICE_TOOLS.each do |name|
      assert File.file?(File.join(TOOLS_ROOT, "voice", name)), "missing tools/voice/#{name}"
      assert File.file?(File.join(TOOLS_ROOT, name)), "legacy entrypoint disappeared: tools/#{name}"
    end
  end

  def test_legacy_entrypoints_delegate_without_owning_implementation
    VOICE_TOOLS.each do |name|
      source = File.read(File.join(TOOLS_ROOT, name))
      assert_includes source, "File.expand_path(\"voice/#{name}\", __dir__)"
      assert_includes source, "load target"
      assert_includes source, "require_relative \"voice/#{name.delete_suffix('.rb')}\""
    end
  end

  def test_rake_tasks_use_canonical_voice_paths
    master_rake = File.read(File.join(MASTER_ROOT, "Rakefile"))
    tools_rake = File.read(File.join(TOOLS_ROOT, "Rakefile"))

    assert_includes master_rake, 'tools/voice/voice_benchmark.rb'
    assert_includes tools_rake, 'File.expand_path("voice/voice_quality.rb", __dir__)'
  end

  def test_path_ownership_declares_the_voice_tools_family
    ownership = YAML.safe_load_file(File.join(MASTER_ROOT, "PATH_OWNERSHIP.yml")).fetch("ownership")
    row = ownership.fetch("tools/voice/")

    assert_includes row.fetch("purpose"), "voice measurement"
    assert_equal "medium", row.fetch("risk")
    assert_includes row.fetch("check"), "rake voice_quality"
  end

  def test_moved_voice_benchmark_resolves_master_paths_from_its_new_directory
    source = File.read(File.join(TOOLS_ROOT, "voice", "voice_benchmark.rb"))

    assert_includes source, 'require_relative "../../lib/master"'
    assert_includes source, 'root = File.expand_path("../..", __dir__)'
  end
end
