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
        assert File.file?(File.join(ROOT, "gates", "#{row.fetch('require')}.rb")),
               "#{name} requires gates/#{row['require']}, which does not exist"
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
      require File.join(ROOT, "gates", "#{row.fetch('require')}.rb")
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
    declared = GATES.reject { |_, row| row.key?("script") }.map { |_, row| File.basename(row["require"]) }
    present = Dir.glob(File.join(ROOT, "gates", "lib", "*.rb")).map { |path| File.basename(path, ".rb") }

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
  # `runner.rb --all` exists and is called by nothing (OPENBSD/data/debt.yml:
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
    assert_includes source, 'RAILS/test/**/*_test.rb'
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
      "calibration" => "layout_suite", "geometry" => "rendered_suite",
    }.each do |leaf, parent|
      assert_equal parent, GATES.dig(leaf, "covered_by"), "#{leaf} should be covered by #{parent}"
    end
    assert_includes File.read(File.join(ROOT, "gates", "runner.rb")), "resolve_gates"
  end

  def test_production_gate_runs_apps_yml_validator_in_process
    source = File.read(File.join(ROOT, "gates", "lib", "production.rb"))
    assert_includes source, "AppsYmlValidator.run"
    assert File.file?(File.join(ROOT, "gates", "lib", "apps_yml.rb"))
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

  # Rails schema files create their tables with `force: :cascade`, so
  # `db:schema:load:queue` drops every table and recreates it empty. Running it
  # on every deploy — which _database.sh did until 2026-08-13 — discards every
  # enqueued background job as a side effect of deploying. brgen was carrying
  # 1670 and had 0 an hour later.
  #
  # It read as harmless because no Solid Queue worker runs on this box, so
  # nothing was going to execute them. That is an argument for fixing it before
  # a worker exists, not after: the first deploy with one would throw away the
  # password-reset emails enqueued while it was running.
  # OpenBSD ships neither lockf(1) nor flock(1) — both are FreeBSD/Linux
  # utilities. `command -v lockf` on vm23 prints nothing.
  #
  # vps_master_scan.sh called `lockf -k "$lock" env ... bin/cli "$@"`, so the
  # documented way to run a MASTER scan on the box exited with "command not
  # found" every time, having taken no lock and run no scan. The failure is
  # silent in the sense that matters: the script's own output says it locked.
  #
  # OPENBSD/bin/with-ci-lock is the same idea in Ruby, which this box has.
  def test_no_script_reaches_for_a_locking_utility_openbsd_lacks
    scripts = Dir.glob("#{File.expand_path("../OPENBSD", ROOT)}/**/*.{sh,ksh,zsh}") +
              Dir.glob("#{ROOT}/**/*.sh").reject { |p| p.include?("/vendor/") }

    offenders = scripts.flat_map do |path|
      File.read(path, encoding: "UTF-8").lines.each_with_index.filter_map do |line, i|
        next if line.strip.start_with?("#")
        next unless line.match?(/(?:\A|[|;&(]|\s)(?:lockf|flock)\s+-/)

        "#{path.sub("#{File.dirname(ROOT)}/", "")}:#{i + 1}"
      end
    end

    assert_empty offenders, "OpenBSD has no lockf(1)/flock(1) — use OPENBSD/bin/with-ci-lock"
  end

  # One CI mutex, not two. The Ruby guard and the shell helper have to name the
  # same file or neither excludes the other, which is what happened: CiGuard
  # locked /var/tmp/pub4-ci.lock while ci_lock.sh pointed three scripts at
  # /var/db/pub4/ci.lock and called itself the single source.
  def test_the_ruby_and_shell_ci_locks_are_the_same_file
    shell = File.read(File.expand_path("../OPENBSD/lib/ci_lock.sh", ROOT), encoding: "UTF-8")
    ruby = File.read(File.join(ROOT, "shared/lib/pub4/ci_guard.rb"), encoding: "UTF-8")

    assert_includes shell, "PUB4_CI_LOCK_DIR=/var/db/pub4"
    assert_includes shell, "PUB4_CI_LOCK_NAME=ci.lock"
    assert_includes ruby, 'LOCK_DIR = "/var/db/pub4"'
    assert_includes ruby, 'DEFAULT_LOCK_PATH = File.join(LOCK_DIR, "ci.lock")'
  end

  def test_secondary_schema_load_is_guarded_by_an_initialisation_check
    source = File.read(File.join(ROOT, "_database.sh"), encoding: "UTF-8")

    assert_includes source, "secondary_db_initialized",
                    "the deploy must check before loading a secondary schema over live data"

    body = source[/rails_prepare_secondary_dbs_as_app\(\).*?\n}/m]

    refute_nil body, "rails_prepare_secondary_dbs_as_app no longer parses as one function"
    assert_includes body, "if secondary_db_initialized",
                    "db:schema:load must sit behind the guard, not beside it"

    guard_line = body.lines.index { |l| l.include?("if secondary_db_initialized") }
    load_line = body.lines.index { |l| l.include?("db:schema:load:${db}") && !l.strip.start_with?("#") }

    assert_operator guard_line, :<, load_line, "the guard must precede the load it guards"
  end

  def test_local_knowledge_corpus_is_not_tracked
    files = git_files("MASTER/knowledge")

    assert_empty files, "MASTER/knowledge is local-only and must remain untracked"
  end

  # Zone files became tracked on 2026-08-12: they are generated by
  # OPENBSD/bin/render_dns.rb, and git is where the SOA serial history has to
  # live — a fresh checkout regenerating them from nothing would restart serials
  # at today's 01 and could hand ns.hyp.net a lower number than it already holds,
  # which makes a secondary refuse every transfer. This used to assert
  # templates-only, and the templates are gone with the loop that read them.
  #
  # The invariant that survives is about what must NOT be tracked. K*.private is
  # a DNSSEC signing key; .zone.signed, K*.key and *.ds are all derived from one
  # and belong only on the box.
  def test_no_dnssec_key_material_is_tracked
    secrets = git_files("OPENBSD/var/nsd").grep(/\.private\z|\.zone\.signed\z|\/K[^\/]+\.key\z|\.ds\z/)

    assert_empty secrets, "DNSSEC key material must never be committed:\n  #{secrets.join("\n  ")}"
  end

  def test_every_nsd_zone_file_is_tracked_and_generated
    tracked = git_files("OPENBSD/var/nsd")

    assert_includes tracked, "OPENBSD/var/nsd/etc/nsd.conf"

    zones = tracked.grep(%r{\AOPENBSD/var/nsd/zones/master/.+\.zone\z})
    assert_operator zones.size, :>=, 50, "expected the generated zone set, found #{zones.size}"

    ungenerated = zones.reject do |rel|
      File.read(File.join(REPO_ROOT, rel)).start_with?("; Generated by OPENBSD/bin/render_dns.rb")
    end
    assert_empty ungenerated, "hand-written zone file(s) — run `ruby OPENBSD/bin/render_dns.rb`:\n  #{ungenerated.join("\n  ")}"
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
