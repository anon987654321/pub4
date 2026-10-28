# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/configuration_guard"
require_relative "../lib/ground/boot_checks"

class TestRuntimeCatalogueValidation < Minitest::Test
  Guard = Master::ConfigurationGuard
  BootChecks = Master::Ground::BootChecks

  def catalogue_path(name)
    File.join(Master::ROOT, "data", name)
  end

  def validated_file(name)
    path = catalogue_path(name)
    Guard.validate(path:, content: File.read(path, encoding: "UTF-8"))
  end

  def test_live_provider_catalogue_satisfies_schema
    assert_nil validated_file("providers.yml")
  end

  def test_live_model_catalogue_satisfies_schema_and_references
    assert_nil validated_file("models.yml")
  end

  def test_provider_registry_rejects_a_non_array_environment_list
    path = catalogue_path("providers.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("openrouter")["env"] = "OPENROUTER_API_KEY"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/provider openrouter\.env must be a unique list/, error)
  end

  def test_unknown_provider_fields_are_rejected
    path = catalogue_path("providers.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("openrouter")["api_key_environemnt"] = "OPENROUTER_API_KEY"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/provider openrouter has unknown field\(s\): api_key_environemnt/, error)
  end

  def test_model_routes_must_reference_declared_tiers
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("routes")["code_generation"] = "catalogue_typo"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models\.yml route code_generation must reference a declared model tier/, error)
  end

  def test_unknown_nested_model_policy_fields_are_rejected
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("routing")["provder"] = "agy"

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/models\.yml routing has unknown field\(s\): provder/, error)
  end

  def test_boot_checks_apply_model_reference_validation_before_startup
    Dir.mktmpdir("master-model-catalogue-boot") do |tmp|
      root = File.join(tmp, "MASTER")
      data_dir = File.join(root, "data")
      FileUtils.mkdir_p(data_dir)

      providers_path = File.join(data_dir, "providers.yml")
      models_path = File.join(data_dir, "models.yml")
      FileUtils.cp(catalogue_path("providers.yml"), providers_path)
      data = YAML.safe_load_file(catalogue_path("models.yml"), aliases: true)
      data.fetch("routes")["code_generation"] = "not_a_tier"
      File.write(models_path, YAML.dump(data))

      result = BootChecks.send(:check_models_yaml, root)

      refute result.ok
      assert_equal :fatal, result.severity
      assert_match(/models\.yml route code_generation must reference a declared model tier/, result.message)
    end
  end

  def test_model_scores_must_stay_in_the_closed_interval
    path = catalogue_path("models.yml")
    data = YAML.safe_load_file(path, aliases: true)
    data.fetch("model_defs").fetch("agy_auto").fetch("score")["quality"] = 1.5

    error = Guard.validate(path:, content: YAML.dump(data))

    assert_match(/model_defs\.agy_auto\.score\.quality must be between 0 and 1/, error)
  end

  def test_canonical_boot_validates_provider_catalogue
    result = BootChecks.send(:check_providers_yaml, Master::ROOT)

    assert result.ok, result.message
    assert_match(/schema and references valid/, result.message)
  end

  def test_canonical_boot_validates_model_catalogue
    result = BootChecks.send(:check_models_yaml, Master::ROOT)

    assert result.ok, result.message
    assert_match(/schema and references valid/, result.message)
  end
end
