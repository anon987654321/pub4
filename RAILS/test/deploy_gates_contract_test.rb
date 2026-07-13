# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class DeployGatesContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("../..", __dir__)
  OPERATOR_ROOT = File.join(REPO_ROOT, "OPERATOR")

  GATE_FILES = %w[
    schema_migration_gate.rb
    generated_asset_freshness_gate.rb
    human_walkthrough_gate.rb
    rails_runtime_gate.rb
  ].freeze

  def test_gate_scripts_exist
    GATE_FILES.each do |name|
      path = File.join(ROOT, name)
      assert File.file?(path), "missing #{name}"
      assert_match(/^(#!|# frozen_string_literal)/, File.read(path, 40), "#{name} should be a Ruby gate script")
    end
  end

  def test_check_rails_wires_new_gates
    source = File.read(File.join(OPERATOR_ROOT, "bin", "check-rails"))
    %w[schema_migration_gate generated_asset_freshness_gate rails_runtime_gate].each do |gate|
      assert_includes source, gate
    end
  end

  def test_check_full_runs_repository_contract_tests
    source = File.read(File.join(OPERATOR_ROOT, "bin", "check-full"))

    assert_includes source, 'runner.run("rails contracts"'
    assert_includes source, 'RAILS/test/**/*_test.rb'
  end

  def test_production_gate_does_not_require_deleted_retired_app_gate
    source = File.read(File.join(ROOT, "check_production_gate.rb"))

    refute_includes source, "archive_restore_gate"
  end

  def test_integrity_gate_wires_new_gates
    integrity = File.read(File.join(OPERATOR_ROOT, "integrity_gate.rb"))
    gates = File.read(File.join(OPERATOR_ROOT, "lib", "gate_environment.rb"))
    assert_includes integrity, "gate_environment"
    assert_includes integrity, "GateEnvironment::INTEGRITY_GATES"
    %w[schema_migration asset_freshness human_walkthrough vps_health].each do |gate|
      assert_includes gates, gate
    end
  end

  def test_operator_surface_files_exist
    %w[bin/vps-state bin/vps-deploy bin/vps-logs bin/post-pull-checklist lib/gate_environment.rb].each do |rel|
      path = File.join(OPERATOR_ROOT, rel)
      assert File.exist?(path), "missing OPERATOR/#{rel}"
    end
    assert File.exist?(File.join(ROOT, "apps.horizon.yml"))
    assert File.exist?(File.join(REPO_ROOT, "RECIPES.md"))
    assert File.exist?(File.join(OPERATOR_ROOT, "data", "debt.yml"))
    assert File.exist?(File.join(OPERATOR_ROOT, "data", "operator.yml"))
    assert File.exist?(File.join(REPO_ROOT, "bin", "pub4"))
    assert File.exist?(File.join(REPO_ROOT, "RAILS", "apps.yml"))
    assert File.exist?(File.join(REPO_ROOT, "OPERATOR", "openbsd", "OPERATOR.sh"))
  end

  def test_bsdports_queue_schema_present
    assert File.file?(File.join(ROOT, "bsdports/db/queue_schema.rb"))
  end

  def test_local_knowledge_corpus_is_not_tracked
    files = git_files("MASTER/knowledge")

    assert_empty files, "MASTER/knowledge is local-only and must remain untracked"
  end

  def test_only_nsd_source_templates_are_tracked
    expected = %w[
      OPENBSD/var/nsd/etc/nsd-zone.tmpl
      OPENBSD/var/nsd/etc/nsd.conf
      OPENBSD/var/nsd/zones/master/zone.tmpl
    ]

    assert_equal expected, git_files("OPENBSD/var/nsd")
  end

  def test_openbsd_contains_only_vps_config_backup
    unexpected = git_files("OPENBSD").reject do |path|
      path.start_with?("OPENBSD/etc/", "OPENBSD/usr/", "OPENBSD/var/")
    end

    assert_empty unexpected, "move OpenBSD tooling to OPERATOR/openbsd: #{unexpected.join(', ')}"
  end

  private

  def git_files(path)
    output, status = Open3.capture2("git", "-C", REPO_ROOT, "ls-files", path)
    assert status.success?, "git ls-files failed for #{path}"
    output.lines.map(&:chomp).reject(&:empty?).sort
  end

end
