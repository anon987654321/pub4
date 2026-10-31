# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../lib/configuration_guard"
require_relative "../lib/ground/boot_checks"

# data/limits.yml held every runtime setting beside a size budget for every
# directory; on 2026-10-31 its sections moved to files named for what they hold
# and the budgets were deleted. Master::CONFIG_FILES maps each section to its
# file, and this holds the map, the readers and the schema to one another.
class TestConfigSections < Minitest::Test
  Guard = Master::ConfigurationGuard
  BootChecks = Master::Ground::BootChecks

  # section => the file that reads it and the text that is the read
  READERS = {
    "autoloop" => ["lib/fix/supervisor.rb", 'config_section("autoloop")'],
    "convergence_discipline" => ["lib/fix/convergence_discipline.rb", 'config_section("convergence_discipline")'],
    "dmesg" => ["lib/trace/dmesg.rb", 'config_section("dmesg")'],
    "fix_budget" => ["lib/fix/run_budget.rb", 'config_section("fix_budget")'],
    "fix_time" => ["lib/fix/run_ledger.rb", 'config_section("fix_time")'],
    "governor" => ["lib/fix/governor.rb", 'config_section("governor")'],
    "process" => ["lib/ops.rb", '"budgets.yml"'],

    "law_groups" => ["lib/cli/scan/request.rb", 'data["law_groups"]'],
    "orientation" => ["lib/ai/orientation.rb", 'config_section("orientation")'],
    "scan_profiles" => ["lib/cli/scan/request.rb", 'config_path("scan_profiles")'],
    "scan_workers" => ["lib/fix/scan/transport.rb", 'config_section("scan_workers")'],
    "session_modes" => ["lib/ground/mode_posture.rb", 'config_path("session_modes"'],
  }.freeze

  def path(file) = File.join(Master::ROOT, "data", file)

  def load(file) = YAML.safe_load_file(path(file), aliases: true)

  def files = Master::CONFIG_FILES.values.uniq

  def test_limits_yml_is_gone
    refute_path_exists path("limits.yml")
  end

  def test_every_mapped_section_has_its_named_reader
    assert_equal READERS.keys.sort, Master::CONFIG_FILES.keys.sort, "a section needs a reader to be mapped"
    READERS.each do |section, (relative, read)|
      refute_nil Master.config_section(section), "#{section} is gone from #{Master::CONFIG_FILES[section]}"
      assert_includes File.read(File.join(Master::ROOT, relative)), read, "#{relative} no longer reads #{section}"
    end
  end

  def test_each_file_satisfies_its_schema
    files.each do |file|
      assert_nil Guard.validate(path: path(file), content: File.read(path(file), encoding: "UTF-8")), file
    end
  end

  def test_unknown_top_level_fields_are_rejected
    data = load("budgets.yml").merge("unexpected_budget" => {})

    reason = Guard.validate(path: path("budgets.yml"), content: YAML.dump(data))

    assert_match(/budgets\.yml has unknown top-level field\(s\): unexpected_budget/, reason)
  end

  def test_scan_profile_must_reference_a_declared_law_group
    data = load("scan.yml")
    data.fetch("scan_profiles").fetch("full")["laws"] = "missing_law_group"

    reason = Guard.validate(path: path("scan.yml"), content: YAML.dump(data))

    assert_match(/scan_profiles\.full\.laws must be '\*' or reference a declared law group/, reason)
  end

  def test_host_specific_resource_thresholds_are_checked_as_rows
    data = load("budgets.yml")
    data.fetch("process").fetch("resources").fetch("process_count").fetch("darwin")["warn"] = "too high"

    reason = Guard.validate(path: path("budgets.yml"), content: YAML.dump(data))

    assert_match(/process\.resources\.process_count\.darwin\.warn must be positive numeric/, reason)
  end

  def test_boot_validates_each_file
    results = BootChecks.send(:check_config_sections_yaml, Master::ROOT)

    assert_equal %w[console_yaml scan_yaml budgets_yaml], results.map(&:name)
    results.each { |result| assert result.ok, result.message }
  end

  def test_boot_rejects_an_invalid_scan_file_before_startup
    data = load("scan.yml")
    data.fetch("session_modes")["default"] = "missing_mode"
    scan = boot_check_with("scan.yml" => data).find { |result| result.name == "scan_yaml" }

    refute scan.ok
    assert_equal :fatal, scan.severity
    assert_match(/session_modes\.default must name a declared mode/, scan.message)
  end

  # The boot checks of a copy of the data files, with +overrides+ written over it.
  def boot_check_with(overrides)
    Dir.mktmpdir("master-config-sections-boot") do |tmp|
      data_dir = File.join(tmp, "MASTER", "data")
      FileUtils.mkdir_p(data_dir)
      files.each { |file| FileUtils.cp(path(file), data_dir) }
      overrides.each { |file, data| File.write(File.join(data_dir, file), YAML.dump(data)) }
      BootChecks.send(:check_config_sections_yaml, File.join(tmp, "MASTER"))
    end
  end

  # guidance.yml is prose for agents. A key there that grows a reader is an
  # enforced setting hiding below the line.
  def test_nothing_reads_guidance
    guidance = load("guidance.yml").fetch("guidance")
    bodies = Dir.glob(File.join(Master::ROOT, "{lib,bin}", "**", "*.rb")).map { |file| File.read(file) }

    assert_operator guidance.size, :>=, 25
    assert(bodies.none? { |body| body.include?("guidance.yml") }, "something reads guidance.yml")
  end
end
