# frozen_string_literal: true

require_relative "test_helper"

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

  def test_pressure_engine_loads_and_instantiates
    engine = Master::PressureEngine.new
    assert_respond_to engine, :ingest
    assert_respond_to engine, :pressure
    assert_kind_of Float, engine.pressure
  end

  def test_hash_dig_compat_returns_nil_for_missing_intermediate_keys
    assert_nil({}.dig(:missing, :nested))
    assert_nil({ outer: {} }.dig(:outer, :missing, :nested))
  end

  def test_hash_dig_compat_preserves_nested_lookup
    assert_equal "value", { outer: { inner: "value" } }.dig(:outer, :inner)
  end

  def test_hash_dig_compat_installation_is_idempotent
    Master.install_hash_dig_compat!
    first_ancestors = Hash.ancestors

    Master.install_hash_dig_compat!

    assert_equal first_ancestors, Hash.ancestors
    assert_equal 1, Hash.ancestors.count { |ancestor| ancestor == Master::HashDigCompat }
  end
end
