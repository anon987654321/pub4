# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../lib/pub4/ci_guard"

class CiGuardTest < Minitest::Test
  def test_enabled_when_env_guard_set
    with_env("PUB4_CI_GUARD" => "1") do
      assert Pub4::CiGuard.enabled?
    end
  end

  def test_disabled_when_env_guard_zero
    with_env("PUB4_CI_GUARD" => "0") do
      refute Pub4::CiGuard.enabled?
    end
  end

  def test_lock_paths_under_var_tmp
    assert_equal "/var/tmp/pub4-ci.lock", Pub4::CiGuard::LOCK_PATH
    assert_equal "/var/tmp/pub4-ci.lock.holder", Pub4::CiGuard::HOLDER_PATH
  end

  private

  def with_env(vars)
    old = vars.keys.to_h { |key| [key, ENV[key]] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    old.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
