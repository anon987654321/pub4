# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"
require_relative "../../MASTER/checks/lib/layout_suite"

class DeployChecksContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("../..", __dir__)
  OPENBSD_ROOT = File.join(REPO_ROOT, "OPENBSD")
  MASTER_CHECKS = File.join(REPO_ROOT, "MASTER", "checks")

  CHECKS = YAML.safe_load_file(File.join(MASTER_CHECKS, "checks.yml")).freeze

  # Every check is declared once, in checks.yml. This used to be four tables that
  # had to agree — runner.rb's CHECK_MAP (name -> file), IN_PROCESS (name ->
  # class), SUBPROCESS_ONLY (their set difference, stored by hand) and
  # CHECK_COVERED_BY — plus 37 shim scripts at the RAILS root whose only job was
  # to require a class the runner already loaded in-process.
  def test_every_check_resolves_to_a_file
    CHECKS.each do |name, row|
      if row.key?("script")
        assert File.file?(File.join(MASTER_CHECKS, row["script"])),
               "#{name} points at checks/#{row['script']}, which does not exist"
      else
        assert File.file?("#{check_file(row)}.rb"),
               "#{name} requires #{row['require']}, which does not exist"
        assert_match(/\ADeploy::\w+\z/, row.fetch("class"), "#{name} needs a Deploy::* class")
      end
    end
  end

  def test_every_check_declares_exactly_one_of_class_or_script
    CHECKS.each do |name, row|
      in_process = row.key?("require") && row.key?("class")
      assert in_process ^ row.key?("script"),
             "#{name} must declare either require+class or script, not both or neither"
    end
  end

  def test_every_composite_names_a_real_check
    CHECKS.each do |name, row|
      parent = row["covered_by"]
      next unless parent

      assert CHECKS.key?(parent), "#{name} is covered_by #{parent}, which is not a check"
      refute_equal name, parent, "#{name} cannot cover itself"
    end
  end

  # Every in-process check loads and answers .run. The old runner named its class
  # in a second table, so a rename could leave IN_PROCESS pointing at a constant
  # that no longer existed and nothing failed until that check was selected.
  def test_every_in_process_check_class_loads
    CHECKS.reject { |_, row| row.key?("script") }.each do |name, row|
      require "#{check_file(row)}.rb"
      klass = Object.const_get(row.fetch("class"))

      assert_respond_to klass, :run, "#{name}: #{row['class']} does not answer .run"
    end
  end

  # The counters checks.yml interpolates into its pass lines.
  def test_pass_message_placeholders_are_known
    known = %w[apps schemas assets]
    CHECKS.each do |name, row|
      next unless row["pass"]

      row["pass"].scan(/%\{(\w+)\}/).flatten.each do |placeholder|
        assert_includes known, placeholder, "#{name} interpolates unknown %{#{placeholder}}"
      end
    end
  end

  # The shims are gone; nothing but the runner should be a check entrypoint.
  def test_no_check_entrypoints_survive_at_the_rails_root
    stragglers = Dir.glob(File.join(ROOT, "*_check.rb")).map { |path| File.basename(path) }

    assert_empty stragglers, "checks are declared in checks.yml and run by checks/runner.rb: #{stragglers}"
  end

  # Inside checks/, the _check suffix says nothing the directory has not already
  # said, and _check_logic only ever existed to avoid colliding with a root shim.
  def test_check_files_carry_no_redundant_suffix
    named = Dir.glob(File.join(MASTER_CHECKS, "**", "*.rb")).map { |path| File.basename(path, ".rb") }
    redundant = named.select { |name| name.end_with?("_check", "_check_logic") }

    assert_empty redundant, "drop the suffix — checks/lib/<name>.rb defines Deploy::<Name>Check: #{redundant}"
  end

  # Support code is not a check. Keeping it in checks/lib/ meant three files
  # (design_metrics, visual_quality, layout_search) each had a near-twin whose
  # name differed only by a suffix.
  def test_checks_lib_holds_only_declared_checks
    declared = CHECKS.reject { |_, row| row.key?("script") }
                    .reject { |_, row| row["require"].to_s.start_with?("MASTER/", "OPENBSD/", "STUDIO/") }
                    .map { |_, row| File.basename(row["require"]) }
    present = Dir.glob(File.join(MASTER_CHECKS, "lib", "**", "*.rb")).map { |path| File.basename(path, ".rb") }

    assert_equal declared.sort, present.sort,
                 "checks/lib/ holds exactly the checks in checks.yml; support code belongs in checks/support/"
  end

  def test_check_rails_wires_herb_check_for_every_rails_surface
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check-rails"))

    assert_includes source, "herb:check"
    assert_includes source, 'File.join("RAILS", app)'
    assert_includes source, '"RAILS/master"'
    assert_includes source, '"BUNDLE_GEMFILE" => File.join(ROOT, app, "Gemfile")'
  end

  def test_check_rails_wires_checks_by_name
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check-rails"))
    assert_includes source, "MASTER/checks/runner.rb"
    %w[schema_migration generated_asset port_inventory production].each do |check|
      assert_match(/"#{check}"/, source, "check-rails should run the #{check} check")
    end
  end

  # A registered check that nothing runs.
  #
  # A check runs when some script names it, names the composite that covers it, or
  # runs `runner.rb --all`, which reaches every check with no covered_by parent;
  # bin/operator check does that through Operator::CheckChain. dns_zones predated
  # that and was the one none of these applied to: registered in checks.yml, complete, and never once executed. When
  # it finally was, it hard-failed on a claim that was not true — one dropped UDP
  # packet out of ~500 queries, reported as a missing DNS record — because a check
  # nobody runs is also a check nobody has seen be wrong.
  #
  # A count would have said 47 checks and meant 46. This asks the question the
  # count cannot.
  CALLER_GLOBS = %w[OPENBSD/bin/* OPENBSD/*.sh OPENBSD/*.rb OPENBSD/lib/*.rb
                    RAILS/*.sh MASTER/bin/* MASTER/lib/operator/*.rb bin/*].freeze

  # Comment lines are stripped first, and that is not tidiness. Written without
  # it, this test passed with the wiring deleted — because the commit that added
  # the wiring also added a comment saying the word "dns_zones", and prose about
  # a check satisfied a check for whether anything runs it. Ruby and zsh share the
  # `#` comment marker, which is the whole of what these callers are.
  def caller_source
    CALLER_GLOBS.flat_map { |glob| Dir[File.join(REPO_ROOT, glob)] }
                .select { |path| File.file?(path) }
                .map { |path| File.read(path, encoding: "UTF-8") }
                .join("\n")
                .lines.reject { |line| line.match?(/\A\s*#/) }.join
  end

  def test_every_registered_check_is_named_by_some_caller
    text = caller_source
    runs_all = text.match?(/"runner\.rb"\),\s*"--all"/)

    orphans = CHECKS.reject do |name, row|
      parent = row["covered_by"]
      next true if runs_all && parent.nil?

      text.match?(/\b#{Regexp.escape(name)}\b/) || (parent && text.match?(/\b#{Regexp.escape(parent)}\b/))
    end.keys

    assert_empty orphans,
                 "these checks are registered in checks.yml and no script in the repo runs them, directly " \
                 "or through their composite — wire each into a check-* entrypoint or delete it"
  end

  # The deploy-time integrity chain names checks instead of pointing at scripts,
  # so it cannot outlive a file the way it did when the shims moved.
  def test_integrity_chain_names_checks_that_exist
    source = File.read(File.join(OPENBSD_ROOT, "lib", "check_environment.rb"))
    assert_includes source, "MASTER/checks/runner.rb"
    source.scan(/RAILS_CHECKS, args: %w\[(\w+)\]/).flatten.each do |check|
      assert CHECKS.key?(check), "integrity chain runs #{check}, which is not in checks.yml"
    end
  end

  def test_check_runs_repository_contract_tests
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check"))

    assert_includes source, 'runner.run("rails contracts"'
    # Was an inline Dir[...].each { require } that loaded all sixty-nine files
    # into one process. run_all.rb runs them one process per file over the same
    # recursive glob, and this pins the step to it so it cannot quietly go back
    # to a loader that shares a namespace across the suite.
    assert_includes source, "RAILS/test/run_all.rb"
    # That run_all.rb reaches test/checks/ is measured by running its file list,
    # in test_the_contract_runner_sees_the_whole_suite below.
  end

  # The runner must actually see every file the old loader saw. A narrower glob
  # here would run 401 of the 496 and print a green line about it.
  def test_the_contract_runner_sees_the_whole_suite
    expected = Dir.glob(File.join(ROOT, "test", "**", "*_test.rb")).sort

    refute_empty expected
    assert_operator expected.size, :>, 50
    assert_includes expected.map { |p| p.sub("#{ROOT}/", "") }, "test/checks/calibration_test.rb",
                    "test/checks/ is part of the suite; a top-level-only glob drops nine files"
  end

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
      phantom_foreign_keys shared_wiring surface_schema design_metrics visual_quality calibration
      page_simulation flow_journey mobile_flow keyboard_flow
    ].each do |check|
      assert CHECKS.key?(check), "checks.yml should register #{check}"
      assert CHECKS.dig(check, "class"), "#{check} should run in-process"
    end
    assert CHECKS.dig("release", "script"), "release still shells out and stays a subprocess"
  end

  def test_check_support_files_exist
    %w[dom_surface_schema guest_flow_persona exemplar_structure visual_quality check_calibration page_inventory]
      .each do |name|
        assert File.file?(File.join(MASTER_CHECKS, "support", "#{name}.rb")), "missing checks/support/#{name}.rb"
      end
    assert File.directory?(File.join(MASTER_CHECKS, "fixtures", "exemplars"))
    assert File.file?(File.join(MASTER_CHECKS, "data", "calibration.yml"))
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
      "calibration" => "layout_suite", "rendered_suite" => "layout_suite", "rendered_geometry" => "rendered_suite",
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

  # Where a check's implementation is, which is not always under checks/. A require
  # naming a tree resolves from the repo root, the way runner.rb resolves it: the
  # checks that measure MASTER's face and the ones that measure the box live with
  # their subject, and only their row lives here.
  def check_file(row)
    required = row.fetch("require")
    base = required.start_with?("MASTER/", "OPENBSD/", "STUDIO/") ? File.expand_path("..", ROOT) : File.join(MASTER_CHECKS)
    File.join(base, required)
  end

end
