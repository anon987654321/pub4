# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"

class DeployGatesContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  REPO_ROOT = File.expand_path("../..", __dir__)
  OPENBSD_ROOT = File.join(REPO_ROOT, "OPENBSD")

  GATES = YAML.safe_load_file(File.join(ROOT, "gates", "gates.yml")).freeze

  # Every gate is declared once, in gates.yml. This used to be four tables that
  # had to agree — runner.rb's GATE_MAP (name -> file), IN_PROCESS (name ->
  # class), SUBPROCESS_ONLY (their set difference, stored by hand) and
  # GATE_COVERED_BY — plus 37 shim scripts at the RAILS root whose only job was
  # to require a class the runner already loaded in-process.
  def test_every_gate_resolves_to_a_file
    GATES.each do |name, row|
      if row.key?("script")
        assert File.file?(File.join(ROOT, "gates", row["script"])),
               "#{name} points at gates/#{row['script']}, which does not exist"
      else
        assert File.file?("#{gate_file(row)}.rb"),
               "#{name} requires #{row['require']}, which does not exist"
        assert_match(/\ADeploy::\w+\z/, row.fetch("class"), "#{name} needs a Deploy::* class")
      end
    end
  end

  def test_every_gate_declares_exactly_one_of_class_or_script
    GATES.each do |name, row|
      in_process = row.key?("require") && row.key?("class")
      assert in_process ^ row.key?("script"),
             "#{name} must declare either require+class or script, not both or neither"
    end
  end

  def test_every_composite_names_a_real_gate
    GATES.each do |name, row|
      parent = row["covered_by"]
      next unless parent

      assert GATES.key?(parent), "#{name} is covered_by #{parent}, which is not a gate"
      refute_equal name, parent, "#{name} cannot cover itself"
    end
  end

  # Every in-process gate loads and answers .run. The old runner named its class
  # in a second table, so a rename could leave IN_PROCESS pointing at a constant
  # that no longer existed and nothing failed until that gate was selected.
  def test_every_in_process_gate_class_loads
    GATES.reject { |_, row| row.key?("script") }.each do |name, row|
      require "#{gate_file(row)}.rb"
      klass = Object.const_get(row.fetch("class"))

      assert_respond_to klass, :run, "#{name}: #{row['class']} does not answer .run"
    end
  end

  # The counters gates.yml interpolates into its pass lines.
  def test_pass_message_placeholders_are_known
    known = %w[apps schemas assets]
    GATES.each do |name, row|
      next unless row["pass"]

      row["pass"].scan(/%\{(\w+)\}/).flatten.each do |placeholder|
        assert_includes known, placeholder, "#{name} interpolates unknown %{#{placeholder}}"
      end
    end
  end

  # The shims are gone; nothing but the runner should be a gate entrypoint.
  def test_no_gate_entrypoints_survive_at_the_rails_root
    stragglers = Dir.glob(File.join(ROOT, "*_gate.rb")).map { |path| File.basename(path) }

    assert_empty stragglers, "gates are declared in gates.yml and run by gates/runner.rb: #{stragglers}"
  end

  # Inside gates/, the _gate suffix says nothing the directory has not already
  # said, and _gate_logic only ever existed to avoid colliding with a root shim.
  def test_gate_files_carry_no_redundant_suffix
    named = Dir.glob(File.join(ROOT, "gates", "**", "*.rb")).map { |path| File.basename(path, ".rb") }
    redundant = named.select { |name| name.end_with?("_gate", "_gate_logic") }

    assert_empty redundant, "drop the suffix — gates/lib/<name>.rb defines Deploy::<Name>Gate: #{redundant}"
  end

  # Support code is not a gate. Keeping it in gates/lib/ meant three files
  # (design_metrics, visual_quality, layout_search) each had a near-twin whose
  # name differed only by a suffix.
  def test_gates_lib_holds_only_declared_gates
    declared = GATES.reject { |_, row| row.key?("script") }
                    .reject { |_, row| row["require"].to_s.start_with?("MASTER/", "OPENBSD/", "STUDIO/") }
                    .map { |_, row| File.basename(row["require"]) }
    present = Dir.glob(File.join(ROOT, "gates", "lib", "**", "*.rb")).map { |path| File.basename(path, ".rb") }

    assert_equal declared.sort, present.sort,
                 "gates/lib/ holds exactly the gates in gates.yml; support code belongs in gates/support/"
  end

  def test_check_rails_wires_gates_by_name
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check-rails"))
    assert_includes source, "RAILS/gates/runner.rb"
    %w[schema_migration generated_asset port_inventory production].each do |gate|
      assert_match(/"#{gate}"/, source, "check-rails should run the #{gate} gate")
    end
  end

  # A registered gate that nothing runs.
  #
  # `runner.rb --all` exists and is called by nothing (TODO.md:
  # rails_gates_not_wired), so a gate is only ever run if some script names it or
  # names the composite that covers it. dns_zones was the one that neither
  # applied to: registered in gates.yml, complete, and never once executed. When
  # it finally was, it hard-failed on a claim that was not true — one dropped UDP
  # packet out of ~500 queries, reported as a missing DNS record — because a gate
  # nobody runs is also a gate nobody has seen be wrong.
  #
  # A count would have said 47 gates and meant 46. This asks the question the
  # count cannot.
  CALLER_GLOBS = %w[OPENBSD/bin/* OPENBSD/*.sh OPENBSD/*.rb OPENBSD/lib/*.rb
                    RAILS/*.sh MASTER/bin/* bin/*].freeze

  # Comment lines are stripped first, and that is not tidiness. Written without
  # it, this test passed with the wiring deleted — because the commit that added
  # the wiring also added a comment saying the word "dns_zones", and prose about
  # a gate satisfied a check for whether anything runs it. Ruby and zsh share the
  # `#` comment marker, which is the whole of what these callers are.
  def caller_source
    CALLER_GLOBS.flat_map { |glob| Dir[File.join(REPO_ROOT, glob)] }
                .select { |path| File.file?(path) }
                .map { |path| File.read(path, encoding: "UTF-8") }
                .join("\n")
                .lines.reject { |line| line.match?(/\A\s*#/) }.join
  end

  def test_every_registered_gate_is_named_by_some_caller
    text = caller_source

    orphans = GATES.reject do |name, row|
      parent = row["covered_by"]
      text.match?(/\b#{Regexp.escape(name)}\b/) || (parent && text.match?(/\b#{Regexp.escape(parent)}\b/))
    end.keys

    assert_empty orphans,
                 "these gates are registered in gates.yml and no script in the repo runs them, directly " \
                 "or through their composite — wire each into a check-* entrypoint or delete it"
  end

  # The deploy-time integrity chain names gates instead of pointing at scripts,
  # so it cannot outlive a file the way it did when the shims moved.
  def test_integrity_chain_names_gates_that_exist
    source = File.read(File.join(OPENBSD_ROOT, "lib", "gate_environment.rb"))
    assert_includes source, "RAILS/gates/runner.rb"
    source.scan(/RAILS_GATES, args: %w\[(\w+)\]/).flatten.each do |gate|
      assert GATES.key?(gate), "integrity chain runs #{gate}, which is not in gates.yml"
    end
  end

  def test_check_full_runs_repository_contract_tests
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check-full"))

    assert_includes source, 'runner.run("rails contracts"'
    # Was an inline Dir[...].each { require } that loaded all sixty-nine files
    # into one process. run_all.rb runs them one process per file over the same
    # `**/*_test.rb` glob -- pinned there, and pinned here so the step cannot
    # quietly go back to a loader that shares a namespace across the suite.
    assert_includes source, "RAILS/test/run_all.rb"

    runner = File.read(File.join(ROOT, "test", "run_all.rb"))
    assert_includes runner, '"**", "*_test.rb"',
                    "run_all.rb must glob recursively or test/gates/ stops being run"
  end

  # The runner must actually see every file the old loader saw. A narrower glob
  # here would run 401 of the 496 and print a green line about it.
  def test_the_contract_runner_sees_the_whole_suite
    expected = Dir.glob(File.join(ROOT, "test", "**", "*_test.rb")).sort

    refute_empty expected
    assert_operator expected.size, :>, 50
    assert_includes expected.map { |p| p.sub("#{ROOT}/", "") }, "test/gates/calibration_test.rb",
                    "test/gates/ is part of the suite; a top-level-only glob drops nine files"
  end

  def test_production_gate_does_not_require_deleted_retired_app_gate
    source = File.read(File.join(ROOT, "gates", "lib", "production.rb"))

    refute_includes source, "archive_restore_gate"
  end

  def test_rails_runtime_gate_runs_production_in_process
    assert File.file?(File.join(ROOT, "gates", "lib", "production.rb"))
    source = File.read(File.join(ROOT, "gates", "rails_runtime.rb"))
    assert_includes source, "Deploy::ProductionGate.run(skip_nested: true)"
    refute_includes source, "GATE_SKIP_NESTED"
  end

  # GATE_SKIP_NESTED was read by the old root shim and ignored by the runner, so
  # the same gate behaved differently depending on how it was invoked. It is now
  # declared on the gate itself.
  def test_production_gate_declares_its_env_flag
    assert_equal({ "GATE_SKIP_NESTED" => "skip_nested" }, GATES.fetch("production").fetch("env_flags"))
  end

  def test_manifest_registers_the_leaf_gates
    %w[
      apps_yml generated_asset human_walkthrough port_inventory schema_migration
      phantom_foreign_keys shared_wiring surface_schema design_metrics visual_quality calibration
      page_simulation flow_journey mobile_flow keyboard_flow
    ].each do |gate|
      assert GATES.key?(gate), "gates.yml should register #{gate}"
      assert GATES.dig(gate, "class"), "#{gate} should run in-process"
    end
    assert GATES.dig("release", "script"), "release still shells out and stays a subprocess"
  end

  def test_gate_support_files_exist
    %w[dom_surface_schema guest_flow_persona exemplar_structure visual_quality gate_calibration page_inventory]
      .each do |name|
        assert File.file?(File.join(ROOT, "gates", "support", "#{name}.rb")), "missing gates/support/#{name}.rb"
      end
    assert File.directory?(File.join(ROOT, "gates", "fixtures", "exemplars"))
    assert File.file?(File.join(ROOT, "gates", "data", "calibration.yml"))
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

  def test_composites_own_their_leaves
    {
      "master_web_assets" => "production", "apps_yml" => "production",
      "domain_alignment" => "release", "surface_schema" => "layout_suite",
      "design_metrics" => "layout_suite", "visual_quality" => "layout_suite",
      "calibration" => "layout_suite", "rendered_geometry" => "rendered_suite",
    }.each do |leaf, parent|
      assert_equal parent, GATES.dig(leaf, "covered_by"), "#{leaf} should be covered by #{parent}"
    end
    assert_includes File.read(File.join(ROOT, "gates", "runner.rb")), "resolve_gates"
  end

  def test_production_gate_runs_apps_yml_validator_in_process
    source = File.read(File.join(ROOT, "gates", "lib", "production.rb"))
    assert_includes source, "AppsYmlValidator.run"
    assert File.file?(File.join(ROOT, "gates", "lib", "source", "apps_yml.rb"))
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
    assert File.exist?(File.join(REPO_ROOT, "TODO.md"))
    assert File.exist?(File.join(OPENBSD_ROOT, "data", "operator.yml"))
    # MASTER/bin/operator, not a root bin/. The repo root holds four documents and
    # the four trees; the operator surface has lived under MASTER since the
    # sprawl census emptied the root, and this line was still looking for the
    # shim that removal deleted.
    assert File.exist?(File.join(REPO_ROOT, "MASTER", "bin", "operator"))
    assert File.exist?(File.join(REPO_ROOT, "RAILS", "apps.yml"))
    assert File.exist?(File.join(REPO_ROOT, "OPENBSD", "OPERATOR.sh"))
  end

  def test_bsdports_queue_schema_present
    assert File.file?(File.join(ROOT, "bsdports/db/queue_schema.rb"))
  end

  # Where a gate's implementation is, which is not always under gates/. A require
  # naming a tree resolves from the repo root, the way runner.rb resolves it: the
  # gates that measure MASTER's face and the ones that measure the box live with
  # their subject, and only their row lives here.
  def gate_file(row)
    required = row.fetch("require")
    base = required.start_with?("MASTER/", "OPENBSD/", "STUDIO/") ? File.expand_path("..", ROOT) : File.join(ROOT, "gates")
    File.join(base, required)
  end

end
