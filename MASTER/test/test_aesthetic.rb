# frozen_string_literal: true

require_relative "test_helper"

class TestAesthetic < Minitest::Test
  def test_defaults_to_wscons
    with_env("MASTER_AESTHETIC" => nil) do
      assert_equal "wscons", Master::Voice::Aesthetic.mode
      assert Master::Voice::Aesthetic.wscons?
      refute Master::Voice::Aesthetic.phosphor?
    end
  end

  def test_phosphor_mode
    with_env("MASTER_AESTHETIC" => "phosphor") do
      assert_equal "phosphor", Master::Voice::Aesthetic.mode
      assert Master::Voice::Aesthetic.phosphor?
    end
  end

  def test_unknown_mode_falls_back_to_wscons
    with_env("MASTER_AESTHETIC" => "neon") do
      assert_equal "wscons", Master::Voice::Aesthetic.mode
    end
  end

  private

  def with_env(overrides)
    saved = {}
    overrides.each_key { |key| saved[key] = ENV.key?(key) ? ENV[key] : :__unset__ }
    overrides.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved&.each do |key, value|
      value == :__unset__ ? ENV.delete(key) : ENV[key] = value
    end
  end
end