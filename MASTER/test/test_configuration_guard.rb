# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/configuration_guard"

class TestConfigurationGuard < Minitest::Test
  Guard = Master::ConfigurationGuard

  def laws_path = File.join(Master::ROOT, "data", "laws.yml")
  def soul_path = File.join(Master::ROOT, "data", "soul.yml")

  def test_current_law_catalogue_satisfies_shared_invariants
    assert_nil Guard.validate(path: laws_path, content: File.read(laws_path, encoding: "UTF-8"))
  end

  def test_current_soul_allows_its_own_safe_edit_path
    assert_nil Guard.validate(path: soul_path, content: File.read(soul_path, encoding: "UTF-8"))
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

  def test_soul_cannot_restore_self_protection_or_broad_data_guards
    data = YAML.safe_load_file(soul_path, aliases: true)
    data.fetch("absolute").fetch("sacred_paths").concat(%w[data/ data/soul.yml data/laws.yml])
    reason = Guard.validate(path: soul_path, content: YAML.dump(data))
    assert_match(/configuration files and retired scanner paths must remain editable/, reason)
  end

  def test_soul_must_keep_the_critical_spine_guarded
    data = YAML.safe_load_file(soul_path, aliases: true)
    data.fetch("absolute")["sacred_paths"].delete("lib/ground/pledge.rb")
    reason = Guard.validate(path: soul_path, content: YAML.dump(data))
    assert_match(/critical path protections missing/, reason)
  end
end
