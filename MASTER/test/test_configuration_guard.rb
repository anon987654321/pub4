# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/configuration_guard"

class TestConfigurationGuard < Minitest::Test
  Guard = Master::ConfigurationGuard

  def laws_path = File.join(Master::ROOT, "data", "laws.yml")
  def soul_path = File.join(Master::ROOT, "data", "soul.yml")
  def tokens_path = File.join(Master::ROOT, "data", "tokens.yml")

  def test_current_law_catalogue_satisfies_shared_invariants
    assert_nil Guard.validate(path: laws_path, content: File.read(laws_path, encoding: "UTF-8"))
  end

  def test_current_soul_allows_its_own_safe_edit_path
    assert_nil Guard.validate(path: soul_path, content: File.read(soul_path, encoding: "UTF-8"))
  end

  def test_current_token_catalogue_satisfies_shared_invariants
    assert_nil Guard.validate(path: tokens_path, content: File.read(tokens_path, encoding: "UTF-8"))
  end

  def test_token_catalogue_cannot_drop_a_required_section
    data = YAML.safe_load_file(tokens_path, aliases: true)
    data.fetch("tokens").delete("face_interface")

    reason = Guard.validate(path: tokens_path, content: YAML.dump(data))

    assert_match(/tokens\.yml is missing required token section\(s\): face_interface/, reason)
  end

  def test_token_catalogue_cannot_drift_a_shared_spacing_contract
    data = YAML.safe_load_file(tokens_path, aliases: true)
    data.fetch("tokens").fetch("pixel_perfection")["eight_px_rhythm"] = [0, 4, 8]

    reason = Guard.validate(path: tokens_path, content: YAML.dump(data))

    assert_match(/tokens\.scale\.space_px must match pixel_perfection\.eight_px_rhythm/, reason)
  end

  def test_face_default_mode_must_exist_in_face_mode_catalogue
    data = YAML.safe_load_file(tokens_path, aliases: true)
    data.fetch("tokens").fetch("face_interface").fetch("state")["default_mode"] = "missing_mode"

    reason = Guard.validate(path: tokens_path, content: YAML.dump(data))

    assert_match(/tokens\.face_interface\.state\.default_mode must be listed in modes/, reason)
  end

  def test_dynamic_tool_catalogue_uses_the_runtime_schema
    path = File.join(Master::ROOT, "data", "tools.dynamic.yml")

    assert_nil Guard.validate(path:, content: File.read(path, encoding: "UTF-8"))
  end

  def test_dynamic_tool_catalogue_cannot_hide_a_mapping_instead_of_a_list
    path = File.join(Master::ROOT, "data", "tools.dynamic.yml")
    content = YAML.dump("name" => "status_ping", "url" => "https://example.com")

    reason = Guard.validate(path:, content:)

    assert_match(/dynamic tool catalogue .* must be a YAML list/, reason)
  end

  def test_malformed_law_yaml_is_refused
    reason = Guard.validate(path: laws_path, content: "law_catalogue: [\n")
    assert_match(/configuration invariant failed/, reason)
  end

  def test_empty_catalogue_is_refused
    reason = Guard.validate(path: laws_path, content: "law_catalogue: {}\n")
    assert_match(/required Law sections missing/, reason)
  end

  def test_catalogue_entry_cannot_drop_a_modality
    data = YAML.safe_load_file(laws_path, aliases: true)
    entry = data.fetch("law_catalogue").fetch("entries").values.first
    entry["modalities"] = %w[lexical semantic]
    reason = Guard.validate(path: laws_path, content: YAML.dump(data))
    assert_match(/modalities must be lexical, semantic, visual/, reason)
  end

  def test_soul_cannot_freeze_the_whole_data_directory
    data = YAML.safe_load_file(soul_path, aliases: true)
    data.fetch("absolute").fetch("sacred_paths").push("data/")
    reason = Guard.validate(path: soul_path, content: YAML.dump(data))
    assert_match(/runtime-written data and retired scanner paths cannot be sacred: data\//, reason)
  end

  # Operator decision 2026-10-28: the laws and the soul are off-limits to automation.
  def test_the_live_soul_protects_the_laws_and_itself
    sacred = YAML.safe_load_file(soul_path, aliases: true).dig("absolute", "sacred_paths")
    assert_includes sacred, "data/laws.yml"
    assert_includes sacred, "data/soul.yml"
  end

  # The required list is the live soul's own, not a copy: dropping any path it declares is refused.
  def test_soul_cannot_drop_a_path_the_live_soul_declares
    data = YAML.safe_load_file(soul_path, aliases: true)
    data.fetch("absolute")["sacred_paths"].delete("data/laws.yml")
    reason = Guard.validate(path: soul_path, content: YAML.dump(data))
    assert_match(/critical path protections missing: data\/laws\.yml/, reason)
  end

  def test_a_new_soul_is_held_to_this_masters_list
    Dir.mktmpdir do |dir|
      path = File.join(dir, "MASTER", "data", "soul.yml")
      data = YAML.safe_load_file(soul_path, aliases: true)
      data.fetch("absolute")["sacred_paths"] = %w[bin/master]
      reason = Guard.validate(path:, content: YAML.dump(data))
      assert_match(/critical path protections missing/, reason)
    end
  end

  def test_soul_must_keep_the_critical_spine_guarded
    data = YAML.safe_load_file(soul_path, aliases: true)
    data.fetch("absolute")["sacred_paths"].delete("lib/ground/pledge.rb")
    reason = Guard.validate(path: soul_path, content: YAML.dump(data))
    assert_match(/critical path protections missing/, reason)
  end
end
