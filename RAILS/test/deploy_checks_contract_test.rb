# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "yaml"
require_relative "../../MASTER/checks/lib/layout_suite"
require_relative "support/deploy_checks_contract_sources"

class DeployChecksContractTest < Minitest::Test
  include DeployChecksContractSources

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
    assert_includes source, 'Hash(meta)["deploy_root"]'
    assert_includes source, '"BUNDLE_GEMFILE" => File.join(ROOT, app, "Gemfile")'
  end

  def test_check_rails_wires_checks_by_name
    source = File.read(File.join(OPENBSD_ROOT, "bin", "check-rails"))
    assert_includes source, "MASTER/checks/runner.rb"
    %w[schema_migration generated_asset port_inventory production].each do |check|
      assert_match(/"#{check}"/, source, "check-rails should run the #{check} check")
    end
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
    assert_includes expected.map { |p| p.sub("#{ROOT}/", "") }, "test/checks/runner_explain_test.rb",
                    "test/checks/ is part of the suite; a top-level-only glob drops nine files"
  end
end
