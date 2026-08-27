# frozen_string_literal: true

require_relative "../test_helper"

# DEBT.md, Test coverage: no test named KeyRotator. It decides which OpenRouter key
# every free-tier call uses, and its "single key makes every method a no-op"
# contract is the kind of thing that quietly becomes false.
class KeyRotatorTest < Minitest::Test
  Rotator = Master::Ground::KeyRotator

  def setup
    @index = Rotator.instance_variable_get(:@index)
  end

  def teardown
    Rotator.instance_variable_set(:@index, @index)
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def long(seed) = seed * Master::MIN_API_KEY_LENGTH_HEURISTIC

  def test_env_vars_come_from_models_yml_or_fall_back
    vars = Rotator.env_vars

    refute_empty vars
    assert_includes vars, "OPENROUTER_API_KEY"
  end

  def test_keys_ignores_unset_and_too_short_values
    with_env(Rotator.env_vars.to_h { |var| [var, nil] }.merge(Rotator.env_vars.first => "short")) do
      assert_empty Rotator.keys
    end
  end

  def test_keys_dedupes_identical_values_across_vars
    vars = Rotator.env_vars
    skip "needs at least two configured key vars" if vars.size < 2

    with_env(vars.to_h { |var| [var, long("a")] }) do
      assert_equal 1, Rotator.keys.size
    end
  end

  def test_active_key_is_nil_without_any_configured_key
    with_env(Rotator.env_vars.to_h { |var| [var, nil] }) do
      assert_nil Rotator.active_key
    end
  end

  # The whole reason this module exists is spreading free-tier limits, so a
  # rotatable model with two keys must actually advance.
  def test_rotation_is_a_noop_with_fewer_than_two_keys
    with_env(Rotator.env_vars.to_h { |var| [var, nil] }.merge(Rotator.env_vars.first => long("a"))) do
      refute Rotator.rotate_for("z-ai/glm-4.5-air:free")
      assert_equal @index, Rotator.instance_variable_get(:@index)
    end
  end

  def test_only_free_tier_and_openrouter_models_rotate
    assert_match Rotator::ROTATABLE_RE, "z-ai/glm-4.5-air:free"
    assert_match Rotator::ROTATABLE_RE, "openrouter/auto"
    refute_match Rotator::ROTATABLE_RE, "grok-4"
    refute_match Rotator::ROTATABLE_RE, "claude-opus-4.5"
    # :free must be a suffix, not a substring anywhere.
    refute_match Rotator::ROTATABLE_RE, "vendor/model:free-preview"
  end

  def test_a_non_rotatable_model_never_advances_the_index
    refute Rotator.rotate_for("grok-4")
    refute Rotator.rotate_for(nil)
    assert_equal @index, Rotator.instance_variable_get(:@index)
  end

  def test_active_key_cycles_through_the_configured_keys
    vars = Rotator.env_vars
    skip "needs at least two configured key vars" if vars.size < 2

    values = vars.each_with_index.to_h { |var, i| [var, long((97 + i).chr)] }
    with_env(values) do
      Rotator.instance_variable_set(:@index, 0)
      first = Rotator.active_key
      Rotator.instance_variable_set(:@index, 1)
      second = Rotator.active_key

      refute_equal first, second
      Rotator.instance_variable_set(:@index, Rotator.keys.size)
      assert_equal first, Rotator.active_key, "index must wrap"
    end
  end
end
