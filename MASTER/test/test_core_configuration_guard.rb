# frozen_string_literal: true

require_relative "test_helper"

class TestCoreConfigurationGuard < Minitest::Test
  def rule
    Master::Core::Constitution.send(
      :configuration_invariant_rule,
      workspace_root: Master::ROOT,
    )
  end

  def effect(path, content)
    Master::Core::Effect.write(path, content)
  end

  def test_default_constitution_uses_the_shared_configuration_guard
    constitution = Master::Core::Constitution.load(data_dir: Master.data_path)

    ids = constitution.instance_variable_get(:@laws).map(&:id)
    assert_includes ids, :configuration_invariant
  end

  def test_existing_law_catalogue_is_eligible_for_edit
    path = File.join(Master::ROOT, "data", "laws.yml")
    verdict = rule.judge.call(effect("data/laws.yml", File.read(path, encoding: "UTF-8")), nil)

    assert_nil verdict
  end

  def test_invalid_law_catalogue_is_blocked_by_schema_not_path
    verdict = rule.judge.call(effect("data/laws.yml", "law_catalogue: {}\n"), nil)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :configuration_invariant, verdict.by
    assert_match(/required Law sections missing/, verdict.reason)
    refute_match(/immutable path/, verdict.reason)
  end

  def test_soul_config_is_editable_only_when_its_invariants_hold
    path = File.join(Master::ROOT, "data", "soul.yml")
    current = File.read(path, encoding: "UTF-8")
    assert_nil rule.judge.call(effect("data/soul.yml", current), nil)

    invalid = current.sub("PRESERVE_THEN_IMPROVE_NEVER_BREAK", "PRESERVE_AND_BREAK")
    verdict = rule.judge.call(effect("data/soul.yml", invalid), nil)
    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :configuration_invariant, verdict.by
    assert_match(/golden_law/, verdict.reason)
  end
end
