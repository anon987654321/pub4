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
  REPO_TOOLS = %w[repo_inventory.rb runs.rb sprawl_plan.rb].freeze
  AUDIT_TOOLS = %w[capability_inventory.rb data_reach.rb design_baseline.rb dup_census.rb law_hygiene.rb].freeze

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
    assert_match(/MASTER_TEST_EXCLUDED = %w\[test\/fixtures\/\*\*\/\* /, rake)

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
    # ROOT is MASTER/, where the challenge balance finds lib/ and test/.
    assert_includes challenges, 'ROOT = File.expand_path("../..", __dir__)'
    assert_includes trajectory, 'MASTER/tools/research/llm_trajectory.rb contract'
  end

  def test_repository_maintenance_implementations_live_in_their_canonical_family
    REPO_TOOLS.each do |name|
      assert File.file?(File.join(TOOLS_ROOT, "repo", name)), "missing tools/repo/#{name}"
      assert File.file?(File.join(TOOLS_ROOT, name)), "legacy entrypoint disappeared: tools/#{name}"
    end
  end

  def test_legacy_repository_entrypoints_delegate_to_canonical_sources
    REPO_TOOLS.each do |name|
      source = File.read(File.join(TOOLS_ROOT, name))
      assert_includes source, "File.expand_path(\"repo/#{name}\", __dir__)"
      assert_includes source, "load target"
      assert_includes source, "require_relative \"repo/#{name.delete_suffix('.rb')}\""
    end
  end

  def test_repository_tools_keep_the_repo_root_when_moved
    inventory = File.read(File.join(TOOLS_ROOT, "repo", "repo_inventory.rb"))
    runs = File.read(File.join(TOOLS_ROOT, "repo", "runs.rb"))
    plan = File.read(File.join(TOOLS_ROOT, "repo", "sprawl_plan.rb"))

    assert_includes inventory, 'INVENTORY_ROOT = File.expand_path("../../..", __dir__)'
    assert_includes runs, 'ROOT = File.expand_path("../../..", __dir__)'
    assert_includes plan, 'ROOT = File.expand_path("../../..", __dir__)'
  end

  def test_audit_implementations_live_in_their_canonical_family
    AUDIT_TOOLS.each do |name|
      assert File.file?(File.join(TOOLS_ROOT, "audit", name)), "missing tools/audit/#{name}"
      refute File.exist?(File.join(TOOLS_ROOT, name)), "no second entrypoint: tools/#{name}"
    end
  end

  def test_audit_sources_keep_their_master_or_repository_root
    capability = File.read(File.join(TOOLS_ROOT, "audit", "capability_inventory.rb"))
    data_reach = File.read(File.join(TOOLS_ROOT, "audit", "data_reach.rb"))
    duplicates = File.read(File.join(TOOLS_ROOT, "audit", "dup_census.rb"))
    law_hygiene = File.read(File.join(TOOLS_ROOT, "audit", "law_hygiene.rb"))

    assert_includes capability, 'MASTER = File.expand_path("../..", __dir__)'
    assert_includes data_reach, 'MASTER_DIR = File.expand_path("../..", __dir__)'
    assert_includes duplicates, 'ROOT = File.expand_path("../../..", __dir__)'
    assert_includes law_hygiene, 'MASTER = File.expand_path("../..", __dir__)'
  end

  def test_path_ownership_declares_the_audit_tools_family
    ownership = YAML.safe_load_file(File.join(MASTER_ROOT, "PATH_OWNERSHIP.yml")).fetch("ownership")
    row = ownership.fetch("tools/audit/")

    assert_includes row.fetch("purpose"), "repository audits for capability inventory"
    assert_equal "medium", row.fetch("risk")
    assert_includes row.fetch("check"), "test_capability_inventory.rb"
  end
  def test_path_ownership_declares_the_repository_tools_family
    ownership = YAML.safe_load_file(File.join(MASTER_ROOT, "PATH_OWNERSHIP.yml")).fetch("ownership")
    row = ownership.fetch("tools/repo/")

    assert_includes row.fetch("purpose"), "tracked-tree inventory"
    assert_equal "medium", row.fetch("risk")
    assert_includes row.fetch("check"), "test_lifecycle_tools.rb"
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

  def test_design_baseline_implementation_lives_in_its_canonical_family
    assert File.file?(File.join(TOOLS_ROOT, "audit", "design_baseline.rb")), "missing tools/audit/design_baseline.rb"
  end

  def test_design_baseline_keeps_master_and_rails_roots_after_the_move
    source = File.read(File.join(TOOLS_ROOT, "audit", "design_baseline.rb"))

    assert_includes source, 'require_relative "../../lib/trace/dmesg"'
    assert_includes source, 'MASTER_ROOT = File.expand_path("../..", __dir__)'
    assert_includes source, 'RAILS_ROOT = File.expand_path("../../../RAILS", __dir__)'
  end

  def test_css_ratchet_runs_the_canonical_design_baseline
    source = File.read(File.join(MASTER_ROOT, "lib", "operator", "ratchets.rb"))

    assert_includes source, 'bundle exec ruby tools/audit/design_baseline.rb'
  end

  def test_design_baseline_is_owned_by_the_audit_family
    ownership = YAML.safe_load_file(File.join(MASTER_ROOT, "PATH_OWNERSHIP.yml")).fetch("ownership")
    row = ownership.fetch("tools/audit/")

    assert_includes row.fetch("purpose"), "design baseline measurements"
    assert_equal "medium", row.fetch("risk")
    assert_includes row.fetch("check"), "test_capability_inventory.rb"
  end

  def test_speech_regression_tests_live_under_the_voice_test_family
    voice_tests = Dir.glob(File.join(MASTER_ROOT, "test", "voice", "test_*.rb")).sort

    assert_operator voice_tests.size, :>=, 8
    voice_tests.each do |path|
      source = File.read(path)
      helper_loaded = source.include?('require_relative "../test_helper"') || source.include?('require "test_helper"')
      assert helper_loaded, "#{path} must load the shared test helper"
    end
  end

  def test_path_ownership_declares_the_voice_test_family
    ownership = YAML.safe_load_file(File.join(MASTER_ROOT, "PATH_OWNERSHIP.yml")).fetch("ownership")
    row = ownership.fetch("test/voice/")

    assert_includes row.fetch("purpose"), "speech and TTS regression tests"
    assert_equal "medium", row.fetch("risk")
    assert_includes row.fetch("check"), "test/voice/test_speech_empty_worker.rb"
  end

end
