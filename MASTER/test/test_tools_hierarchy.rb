# frozen_string_literal: true

require_relative "test_helper"
require "yaml"
require "tmpdir"
require "fileutils"

class TestToolsHierarchy < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  MASTER_ROOT = File.join(REPO_ROOT, "MASTER")
  TOOLS_ROOT = File.join(MASTER_ROOT, "tools")
  VOICE_TOOLS = %w[voice_benchmark.rb voice_measure.rb voice_quality.rb].freeze
  RESEARCH_TOOLS = %w[cognition_benchmark.rb llm_challenges.rb llm_trajectory.rb].freeze

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

  def test_master_test_discovery_is_recursive_for_both_test_naming_forms
    rake = File.read(File.join(MASTER_ROOT, "Rakefile"))
    assert_includes rake, 'FileList["test/**/test_*.rb", "test/**/*_test.rb"]'
    assert_includes rake, '"test/fixtures/**/*"'

    Dir.mktmpdir do |root|
      test_root = File.join(root, "test")
      FileUtils.mkdir_p(File.join(test_root, "voice"))
      FileUtils.mkdir_p(File.join(test_root, "fixtures"))
      first = File.join(test_root, "voice", "test_voice_quality.rb")
      second = File.join(test_root, "voice", "voice_quality_test.rb")
      fixture = File.join(test_root, "fixtures", "test_example.rb")
      [first, second, fixture].each { |path| File.write(path, "# fixture\\n") }

      found = (Dir.glob(File.join(test_root, "**", "test_*.rb")) +
               Dir.glob(File.join(test_root, "**", "*_test.rb"))).uniq
      fixtures = File.join(test_root, "fixtures") + File::SEPARATOR
      found.reject! { |path| path.start_with?(fixtures) }

      assert_equal [first, second].sort, found.sort
    end
  end

  def test_research_implementations_live_in_their_canonical_family
    RESEARCH_TOOLS.each do |name|
      assert File.file?(File.join(TOOLS_ROOT, "research", name)), "missing tools/research/#{name}"
      assert File.file?(File.join(TOOLS_ROOT, name)), "legacy entrypoint disappeared: tools/#{name}"
    end
  end

  def test_legacy_research_entrypoints_delegate_to_canonical_sources
    RESEARCH_TOOLS.each do |name|
      source = File.read(File.join(TOOLS_ROOT, name))
      assert_includes source, "File.expand_path(\"research/#{name}\", __dir__)"
      assert_includes source, "load target"
      assert_includes source, "require_relative \"research/#{name.delete_suffix('.rb')}\""
    end
  end

  def test_research_source_paths_and_invocation_examples_use_the_new_directory
    cognition = File.read(File.join(TOOLS_ROOT, "research", "cognition_benchmark.rb"))
    challenges = File.read(File.join(TOOLS_ROOT, "research", "llm_challenges.rb"))
    trajectory = File.read(File.join(TOOLS_ROOT, "research", "llm_trajectory.rb"))

    assert_includes cognition, 'require_relative "../../lib/cognition/benchmark"'
    assert_includes challenges, 'ROOT = File.expand_path("../../..", __dir__)'
    assert_includes trajectory, 'MASTER/tools/research/llm_trajectory.rb contract'
  end

  def test_path_ownership_declares_the_research_tools_family
    ownership = YAML.safe_load_file(File.join(MASTER_ROOT, "PATH_OWNERSHIP.yml")).fetch("ownership")
    row = ownership.fetch("tools/research/")

    assert_includes row.fetch("purpose"), "cognition benchmarks"
    assert_equal "medium", row.fetch("risk")
    assert_includes row.fetch("check"), "test_cognition_outcome_model.rb"
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
