# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class DeployGatesContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("../..", __dir__)
  OPENBSD_ROOT = File.join(REPO_ROOT, "OPENBSD")

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
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check-rails"))
    %w[schema_migration_gate generated_asset_freshness_gate rails_runtime_gate].each do |gate|
      assert_includes source, gate
    end
  end

  def test_check_full_runs_repository_contract_tests
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check-full"))

    assert_includes source, 'runner.run("rails contracts"'
    assert_includes source, 'RAILS/test/**/*_test.rb'
  end

  def test_production_gate_does_not_require_deleted_retired_app_gate
    source = File.read(File.join(ROOT, "check_production_gate.rb"))

    refute_includes source, "archive_restore_gate"
  end

  def test_production_gate_runs_in_process_from_lib
    assert File.file?(File.join(ROOT, "gates", "lib", "production_gate.rb"))
    source = File.read(File.join(ROOT, "rails_runtime_gate.rb"))
    assert_includes source, "Deploy::ProductionGate.run(skip_nested: true)"
    refute_includes source, "GATE_SKIP_NESTED"
  end

  def test_runner_registers_apps_yml_validator
    source = File.read(File.join(ROOT, "gates", "runner.rb"))
    assert_includes source, "apps_yml:"
    assert_includes source, %q{"apps_yml_validator.rb"}
  end

  def test_runner_runs_leaf_gates_in_process
    source = File.read(File.join(ROOT, "gates", "runner.rb"))
    assert_includes source, "IN_PROCESS"
    assert_includes source, "run_in_process"
    %w[generated_asset human_walkthrough port_inventory schema_migration phantom_foreign_keys shared_wiring].each do |key|
      assert_match(/#{key}:\s+\[/, source, "runner IN_PROCESS should include #{key}")
    end
    assert_includes source, "SUBPROCESS_ONLY"
    assert_includes source, ":release"
  end

  def test_leaf_gate_lib_classes_exist
    %w[
      generated_asset_gate
      human_walkthrough_gate
      port_inventory_gate
      schema_migration_gate
      phantom_foreign_keys_gate
      surface_schema_gate
      dom_surface_schema
      guest_flow_persona
    ].each do |name|
      assert File.file?(File.join(ROOT, "gates", "lib", "#{name}.rb")), "missing gates/lib/#{name}.rb"
    end
  end

  def test_runner_registers_surface_schema
    source = File.read(File.join(ROOT, "gates", "runner.rb"))
    assert_includes source, "surface_schema:"
    assert_includes source, "SurfaceSchemaGate"
  end

  def test_runner_registers_design_metrics
    source = File.read(File.join(ROOT, "gates", "runner.rb"))
    assert_includes source, "design_metrics:"
    assert_includes source, "DesignMetricsGate"
    assert File.file?(File.join(ROOT, "gates", "lib", "design_metrics.rb"))
    assert File.file?(File.join(ROOT, "gates", "lib", "design_metrics_gate.rb"))
  end

  def test_surface_schema_fixtures_exist
    dir = File.join(ROOT, "gates", "fixtures", "surfaces")
    assert File.directory?(dir)
    assert Dir.glob(File.join(dir, "good_*.html")).size >= 4
    assert Dir.glob(File.join(dir, "bad_*.html")).size >= 4
  end

  def test_gate_result_supports_severity
    source = File.read(File.join(OPENBSD_ROOT, "lib", "gate_result.rb"))
    assert_includes source, "severity:"
    assert_includes source, "soft_failures"
    assert_includes source, "GATE_STRICT_SOFT"
  end

  def test_runner_deduplicates_leaf_gates_under_composites
    source = File.read(File.join(ROOT, "gates", "runner.rb"))
    assert_includes source, "GATE_COVERED_BY"
    assert_includes source, "resolve_gates"
    assert_match(/master_web_assets:\s*:production/, source)
    assert_match(/apps_yml:\s*:production/, source)
    assert_match(/domain_alignment:\s*:release/, source)
    assert_match(/surface_schema:\s*:layout_suite/, source)
    assert_match(/design_metrics:\s*:layout_suite/, source)
  end

  def test_production_gate_runs_apps_yml_validator_in_process
    source = File.read(File.join(ROOT, "gates", "lib", "production_gate.rb"))
    assert_includes source, "AppsYmlValidator.run"
    assert File.file?(File.join(ROOT, "gates", "lib", "apps_yml_validator.rb"))
  end

  def test_deploy_at_aliases_are_retired
    %w[@core.sh @database.sh @deploy.sh @runtime_gate.sh @scaffold.sh @service.sh @sync.sh].each do |name|
      refute File.exist?(File.join(ROOT, name)),
             "#{name} resurrected — canonical scripts are the _*.sh files"
    end
  end

  def test_integrity_gate_wires_new_gates
    integrity = File.read(File.join(OPENBSD_ROOT, "integrity_gate.rb"))
    gates = File.read(File.join(OPENBSD_ROOT, "lib", "gate_environment.rb"))
    assert_includes integrity, "gate_environment"
    assert_includes integrity, "GateEnvironment::INTEGRITY_GATES"
    %w[schema_migration asset_freshness human_walkthrough vps_health].each do |gate|
      assert_includes gates, gate
    end
  end

  def test_operator_surface_files_exist
    %w[bin/vps-state bin/vps-deploy bin/vps-logs bin/post-pull-checklist lib/gate_environment.rb].each do |rel|
      path = File.join(OPENBSD_ROOT, rel)
      assert File.exist?(path), "missing OPENBSD/#{rel}"
    end
    assert File.exist?(File.join(ROOT, "apps.horizon.yml"))
    assert File.exist?(File.join(REPO_ROOT, "OPENBSD", "RECIPES.md"))
    assert File.exist?(File.join(REPO_ROOT, "RAILS", "deploy.sh"))
    assert File.exist?(File.join(OPENBSD_ROOT, "data", "debt.yml"))
    assert File.exist?(File.join(OPENBSD_ROOT, "data", "operator.yml"))
    assert File.exist?(File.join(REPO_ROOT, "bin", "pub4"))
    assert File.exist?(File.join(REPO_ROOT, "RAILS", "apps.yml"))
    assert File.exist?(File.join(REPO_ROOT, "OPENBSD", "OPERATOR.sh"))
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

  def test_openbsd_has_operator_surfaces
    %w[
      OPENBSD/OPERATOR.sh
      OPENBSD/bin/check
      OPENBSD/lib/gate_environment.rb
      OPENBSD/integrity_gate.rb
      OPENBSD/vps_ci.sh
    ].each do |rel|
      assert File.exist?(File.join(REPO_ROOT, rel)), "missing #{rel}"
    end
  end

  def test_shared_search_partials_are_not_duplicated_per_app
    %w[_search_loading.html.erb _search_suggestions.html.erb].each do |partial|
      canonical = File.join(ROOT, "shared", "app", "views", "shared", partial)
      assert_path_exists canonical

      %w[amber brgen bsdports].each do |app|
        duplicate = File.join(ROOT, app, "app", "views", "shared", partial)
        refute_path_exists duplicate, "#{app} must use shared/#{partial} from the shared engine"
      end
    end
  end

  def test_comment_destroy_stream_is_shared
    canonical = File.join(ROOT, "shared", "app", "views", "comments", "destroy.turbo_stream.erb")
    assert_path_exists canonical

    %w[amber brgen bsdports].each do |app|
      duplicate = File.join(ROOT, app, "app", "views", "comments", "destroy.turbo_stream.erb")
      refute_path_exists duplicate, "#{app} must use the shared comment destroy stream"
    end
  end

  private

  def git_files(path)
    output, status = Open3.capture2("git", "-C", REPO_ROOT, "ls-files", path)
    assert status.success?, "git ls-files failed for #{path}"
    output.lines.map(&:chomp).reject(&:empty?).sort
  end

end
