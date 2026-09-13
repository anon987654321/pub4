# frozen_string_literal: true

require_relative "test_helper"
require "open3"

class MasterBootTest < Minitest::Test
  def test_boot_loader_requires_all_modules
    assert defined?(MasterPaths)
    assert defined?(Master::DataLoading)
    assert defined?(Master::MasterRuntime)
    assert defined?(Master::MasterBoot)
  end

  def test_master_paths_shim_matches_boot_paths
    assert_equal MasterPaths::ROOT, File.expand_path("..", File.expand_path("../lib", __dir__))
    assert MasterPaths.data("rules.yml").end_with?("/data/rules.yml")
  end

  def test_master_data_load_yaml_reads_rules
    path = Master.data_path("rules.yml")

    body = Master.load_yaml(path)
    assert body.is_a?(Hash)
    assert body.key?("rules")
  end

  def test_master_runtime_process_defaults_constant
    assert_includes Master::MasterRuntime::PROCESS_DEFAULTS, "MASTER_SAFE_MODE"
    assert_equal "1", Master::MasterRuntime::PROCESS_DEFAULTS["MASTER_SAFE_MODE"]
  end

  def test_master_boot_module_exposes_boot_entrypoints
    assert Master.respond_to?(:boot)
    assert Master.respond_to?(:prepare_runtime!)
    assert Master.respond_to?(:validate_data!)
  end

  # In a child process, because the install prepends onto Hash for good and
  # this suite must keep MRI's dig. The child plants coltrane 2.1.5's
  # replacement, shows it raising, then installs the compat twice.
  COLTRANE_DIG_PROBE = <<~RUBY
    require #{File.expand_path("../lib/boot/hash_dig_compat", __dir__).inspect}
    class Hash
      def dig(*args) = args.size > 1 ? self[args.shift].dig(*args) : self[args[0]]
    end
    broken = begin
      {}.dig(:missing, :nested)
      "no-raise"
    rescue NoMethodError
      "raised"
    end
    Master.install_hash_dig_compat!
    Master.install_hash_dig_compat!
    puts [broken, {}.dig(:missing, :nested).inspect, { outer: {} }.dig(:outer, :missing, :nested).inspect,
          { outer: { inner: "value" } }.dig(:outer, :inner),
          Hash.ancestors.count { |a| a == Master::HashDigCompat }].join(" ")
  RUBY

  def test_hash_dig_compat_repairs_coltrane_dig_and_installs_once
    out, status = Open3.capture2e(RbConfig.ruby, "-e", COLTRANE_DIG_PROBE)

    assert status.success?, out
    assert_equal "raised nil nil value 1", out.strip
  end

  def test_the_suite_runs_on_mris_dig
    refute_includes Hash.ancestors.map(&:to_s), "Master::HashDigCompat"
  end
end
