# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/demo_media"

class DemoMediaTest < Minitest::Test
  def test_skip_attach_when_env_flag_set
    refute Shared::DemoMedia.skip_attach? unless ENV["SKIP_DEMO_MEDIA"]
  end

  def test_skip_attach_with_env_override
    with_env("SKIP_DEMO_MEDIA" => "1") do
      assert Shared::DemoMedia.skip_attach?
    end
  end

  private

  def with_env(overrides)
    backup = overrides.keys.to_h { |key| [key, ENV[key]] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    backup.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end