# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"
require_relative "../../MASTER/checks/lib/layout_suite"
require_relative "support/deploy_checks_contract_sources"

class DeployChecksRuntimeTest < Minitest::Test
  include DeployChecksContractSources

  def test_production_check_does_not_require_deleted_retired_app_check
    source = File.read(File.join(MASTER_CHECKS, "lib", "production.rb"))

    refute_includes source, "archive_restore_check"
  end

  def test_rails_runtime_check_fails_closed_when_master_scan_is_unavailable
    source = File.read(File.join(ROOT, "_runtime_check.sh"))
    start = source.index("master_scan_dep()")
    body = source[start, source.index("\n}\n", start) - start + 3]

    assert_match(/\[\[ -x \$\{master\}\/bin\/master \]\] \|\| \{.*return 1; \}/m, body)
    refute_match(/\[\[ -x \$\{master\}\/bin\/master \]\] \|\| return 0/, body)
    assert_includes body, "var/db/pub4"
  end

  def test_rails_runtime_check_fails_closed_when_app_directory_is_missing
    source = File.read(File.join(ROOT, "_runtime_check.sh"))
    start = source.index("rails_runtime_check()")
    body = source[start, source.index("\n}\n", start) - start + 3]

    missing = body[/\[\[ -d \$app_dir \]\] \|\| \{(.*?)\n  \}/m, 1].to_s

    assert_match(/log_err.*return 1/m, missing)
    refute_match(/return 0/, missing)
  end

  def test_rails_runtime_check_fails_closed_when_named_app_ci_is_missing
    source = File.read(File.join(ROOT, "_runtime_check.sh"))
    start = source.index("rails_runtime_check()")
    body = source[start, source.index("\n}\n", start) - start + 3]

    assert_match(/\[\[ -x \$\{app_dir\}\/bin\/ci \]\] \|\| \{.*return 1/m, body)
    refute_match(/if \[\[ -x \$\{app_dir\}\/bin\/ci \]\]; then/, body)
  end

  def test_rails_runtime_check_fails_closed_when_generic_ci_is_missing
    source = File.read(File.join(ROOT, "_runtime_check.sh"))
    start = source.index("rails_runtime_check()")
    body = source[start, source.index("\n}\n", start) - start + 3]
    generic = body.split(/^  else\s*$/).last

    assert_match(/\[\[ -x \$\{app_dir\}\/bin\/ci \]\] \|\| \{.*return 1/m, generic)
    refute_match(/if \[\[ -x \$\{app_dir\}\/bin\/ci \]\]; then/, generic)
  end

  def test_rails_master_scan_skip_requires_explicit_acknowledgement
    source = File.read(File.join(ROOT, "_runtime_check.sh"))
    start = source.index("master_scan_dep()")
    body = source[start, source.index("\n}\n", start) - start + 3]

    assert_includes body, '[[ ${SKIP_MASTER_SCAN:-0} != 0 ]]'
    assert_includes body, '[[ ${SKIP_MASTER_SCAN} != 1 || ${I_UNDERSTAND_FAST_DEPLOY:-0} != 1 ]]'
    assert_includes body, "SKIP_MASTER_SCAN=1 requires I_UNDERSTAND_FAST_DEPLOY=1"
    refute_includes body, '[[ -n ${SKIP_MASTER_SCAN:-} ]]'
  end

  def test_database_secret_reader_uses_zsh_native_parsing
    source = File.read(File.join(ROOT, "_database.sh"))
    start = source.index("app_secret_for()")
    body = source[start, source.index("\n}\n", start) - start + 3]

    refute_match(/\|\s*(?:head|cut)\b/, body)
    assert_includes body, "pub4-admin ensure-secret", "the broker owns the secret file; nothing here parses it"
    assert_match(/\*\[!0123456789abcdefABCDEF\]\*\)/, body, "a non-hex answer from the broker is refused")
  end

  def test_rails_runtime_check_runs_production_in_process
    assert File.file?(File.join(MASTER_CHECKS, "lib", "production.rb"))
    source = File.read(File.join(MASTER_CHECKS, "rails_runtime.rb"))
    assert_includes source, "Deploy::ProductionCheck.run(skip_nested: true)"
    refute_includes source, "CHECK_SKIP_NESTED"
  end

  # CHECK_SKIP_NESTED was read by the old root shim and ignored by the runner, so
  # the same check behaved differently depending on how it was invoked. It is now
  # declared on the check itself.
  def test_production_check_declares_its_env_flag
    assert_equal({ "CHECK_SKIP_NESTED" => "skip_nested" }, CHECKS.fetch("production").fetch("env_flags"))
  end

  def test_manifest_registers_the_leaf_checks
    %w[
      apps_yml generated_asset human_walkthrough port_inventory schema_migration
      phantom_foreign_keys shared_wiring surface_schema design_metrics visual_quality
      page_simulation flow_journey mobile_flow keyboard_flow
    ].each do |check|
      assert CHECKS.key?(check), "checks.yml should register #{check}"
      assert CHECKS.dig(check, "class"), "#{check} should run in-process"
    end
    assert CHECKS.dig("release", "script"), "release still shells out and stays a subprocess"
  end

  def test_check_support_files_exist
    %w[dom_surface_schema guest_flow_persona exemplar_structure visual_quality page_inventory]
      .each do |name|
        assert File.file?(File.join(MASTER_CHECKS, "support", "#{name}.rb")), "missing checks/support/#{name}.rb"
      end
    assert File.directory?(File.join(MASTER_CHECKS, "fixtures", "exemplars"))
  end

  def test_surface_schema_fixtures_exist
    dir = File.join(MASTER_CHECKS, "fixtures", "surfaces")
    assert File.directory?(dir)
    assert Dir.glob(File.join(dir, "good_*.html")).size >= 4
    assert Dir.glob(File.join(dir, "bad_*.html")).size >= 4
  end

  def test_json_ld_views_use_the_shared_safe_serializer
    view_paths = Dir.glob(File.join(ROOT, "**", "app", "views", "**", "*.erb"))
    raw_json_ld = view_paths.filter_map do |path|
      source = File.read(path)
      next unless source.match?(/<script\b(?=[^>]*\btype\s*=\s*["']application\/ld\+json["'])/im)

      path.delete_prefix(REPO_ROOT + File::SEPARATOR)
    end

    assert_empty raw_json_ld,
                 "JSON-LD view tags must go through the shared safe serializer: #{raw_json_ld.join(', ')}"

    helper_path = File.join(REPO_ROOT, "RAILS", "__shared", "app", "helpers", "shared", "seo_kit.rb")
    helper = File.read(helper_path)
    assert_match(/def json_ld_script\b/, helper)
    assert_includes helper, "json_escape(data.to_json)"
    assert_includes helper, 'type: "application/ld+json"'
  end

  def test_check_result_supports_severity
    source = File.read(File.join(MASTER_CHECKS, "support", "check_result.rb"))
    assert_includes source, "severity:"
    assert_includes source, "soft_failures"
    assert_includes source, "CHECK_STRICT_SOFT"
  end

  # A covered_by edge is a promise, not a label: --all omits child checks only
  # because the named composite runs them. Keep the registry and its actual leaf
  # list identical so a registered check cannot silently disappear from coverage.
  def test_layout_suite_runs_exactly_its_registered_leaves
    expected = CHECKS.select { |_, row| row["covered_by"] == "layout_suite" }
                   .values.map { |row| row.fetch("class") }.sort
    actual = Deploy::LayoutSuiteCheck::LEAVES.map(&:name).sort

    assert_equal expected, actual,
                 "layout_suite membership must match checks.yml covered_by entries exactly"
  end

  def test_composites_own_their_leaves
    {
      "master_web_assets" => "production", "apps_yml" => "production",
      "domain_alignment" => "release", "security_headers_source" => "release",
      "surface_schema" => "layout_suite",
      "design_metrics" => "layout_suite", "visual_quality" => "layout_suite",
      "rendered_suite" => "layout_suite", "rendered_geometry" => "rendered_suite",
    }.each do |leaf, parent|
      assert_equal parent, CHECKS.dig(leaf, "covered_by"), "#{leaf} should be covered by #{parent}"
    end
    assert_includes File.read(File.join(MASTER_CHECKS, "runner.rb")), %(["covered_by"])
  end

  def test_security_headers_source_contract_is_owned_by_release
    source = File.read(File.join(MASTER_CHECKS, "release.rb"))
    assert_includes source, "Deploy::SecurityHeadersSourceCheck"
    assert_equal "release", CHECKS.dig("security_headers_source", "covered_by")
  end

  def test_apps_yml_validator_points_at_the_canonical_rails_inventory
    source = File.read(File.join(REPO_ROOT, "MASTER", "checks", "lib", "source", "apps_yml.rb"))
    assert_includes source, 'ROOT = File.join(REPO_ROOT, "RAILS")'
    assert File.file?(File.join(REPO_ROOT, "RAILS", "apps.yml"))
  end

  def test_production_check_runs_apps_yml_validator_in_process
    source = File.read(File.join(MASTER_CHECKS, "lib", "production.rb"))
    assert_includes source, "AppsYmlValidator.run"
    assert File.file?(File.join(MASTER_CHECKS, "lib", "source", "apps_yml.rb"))
  end

  def test_deploy_at_aliases_are_retired
    %w[@core.sh @database.sh @deploy.sh @runtime_check.sh @scaffold.sh @service.sh @sync.sh].each do |name|
      refute File.exist?(File.join(ROOT, name)),
             "#{name} resurrected — canonical scripts are the _*.sh files"
    end
  end

  def test_integrity_check_wires_new_checks
    integrity = File.read(File.join(OPENBSD_ROOT, "checks", "integrity_check.rb"))
    checks = File.read(File.join(OPENBSD_ROOT, "lib", "check_environment.rb"))
    assert_includes integrity, "check_environment"
    assert_includes integrity, "CheckEnvironment::INTEGRITY_CHECKS"
    %w[schema_migration asset_freshness human_walkthrough vps_health].each do |check|
      assert_includes checks, check
    end
  end

  # The operator's recipes are data in operator.yml: each says what you want,
  # what to run and what to expect. A recipe naming a script that has moved
  # hands the operator a command that fails, so every tree path a `run` names
  # has to exist.
  def test_operator_recipes_name_commands_that_exist
    recipes = YAML.safe_load_file(File.join(OPENBSD_ROOT, "data", "operator.yml"), aliases: true).fetch("recipes")
    refute_empty recipes, "operator.yml has no recipes — the parse broke, not the tree"

    incomplete = recipes.reject { |r| %w[want run expect].all? { |k| r[k].to_s.strip != "" } }
    assert_empty incomplete.map { |r| r["want"] }, "recipes missing want, run or expect"

    missing = recipes.flat_map do |recipe|
      recipe["run"].scan(%r{\b(?:MASTER|OPENBSD|RAILS|STUDIO)/[\w./-]+}).reject do |path|
        File.exist?(File.join(REPO_ROOT, path))
      end.map { |path| "#{recipe["want"]}: #{path}" }
    end
    assert_empty missing, "operator.yml recipes run paths that do not exist"
  end

  def test_operator_surface_files_exist
    %w[bin/vps-state bin/vps-deploy bin/vps-logs bin/post-pull-checklist lib/check_environment.rb].each do |rel|
      path = File.join(OPENBSD_ROOT, rel)
      assert File.exist?(path), "missing OPENBSD/#{rel}"
    end
    assert File.exist?(File.join(ROOT, "apps.horizon.yml"))
    assert File.exist?(File.join(REPO_ROOT, "RAILS", "deploy.sh"))
    assert File.exist?(File.join(REPO_ROOT, "MASTER", "data", "operator_seams.yml"))
    assert File.exist?(File.join(OPENBSD_ROOT, "data", "operator.yml"))
    # MASTER/bin/operator, not a root bin/. The repo root holds four documents and
    # the four governed trees; the operator surface has lived under MASTER since the
    # sprawl census emptied the root, and this line was still looking for the
    # shim that removal deleted.
    assert File.exist?(File.join(REPO_ROOT, "MASTER", "bin", "operator"))
    assert File.exist?(File.join(REPO_ROOT, "RAILS", "apps.yml"))
    assert File.exist?(File.join(REPO_ROOT, "OPENBSD", "OPERATOR.sh"))
  end

  def test_bsdports_queue_schema_present
    assert File.file?(File.join(ROOT, "bsdports/db/queue_schema.rb"))
  end
end
