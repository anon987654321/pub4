# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/shared/vapid"

class VapidTest < Minitest::Test
  def test_configured_reflects_env
    with_env("VAPID_PUBLIC_KEY" => "", "VAPID_PRIVATE_KEY" => "") do
      refute Shared::Vapid.configured?
    end
    with_env("VAPID_PUBLIC_KEY" => "pub", "VAPID_PRIVATE_KEY" => "priv") do
      assert Shared::Vapid.configured?
      assert_equal "pub", Shared::Vapid.webpush_options[:public_key]
    end
  end

  private

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
