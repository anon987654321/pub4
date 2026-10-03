# frozen_string_literal: true

require "minitest/autorun"
require "rbconfig"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__))
require_relative "../../app/services/shared/dilla_processor"

# dilla has hung indefinitely in the past, pinning a Solid Queue worker forever.
# run_with_timeout must free the worker and kill the child instead of blocking.
class DillaProcessorTest < Minitest::Test
  def test_successful_command_returns_true
    ok = Shared::DillaProcessor.run_with_timeout({}, [ RbConfig.ruby, "-e", "STDOUT.puts 'done'" ])
    assert_equal true, ok
  end

  def test_failing_command_returns_false
    ok = Shared::DillaProcessor.run_with_timeout({}, [ RbConfig.ruby, "-e", "exit 1" ])
    assert_equal false, ok
  end

  def test_normalize_style_collapses_hyphen_and_underscore
    assert_equal "neo_soul", Shared::DillaProcessor.normalize_style("neo-soul")
    assert_equal "neo_soul", Shared::DillaProcessor.normalize_style("neo_soul")
    assert_equal "dilla", Shared::DillaProcessor.normalize_style("not-a-style")
  end

  def test_hung_command_times_out_quickly_instead_of_blocking
    with_env("DILLA_SH_TIMEOUT" => "1") do
      started = Time.now
      ok = Shared::DillaProcessor.run_with_timeout({}, [ RbConfig.ruby, "-e", "sleep 30" ])
      elapsed = Time.now - started

      assert_equal false, ok, "a render past the timeout must fail, not succeed"
      assert_operator elapsed, :<, 10, "must return near the 1s timeout, not wait out the 30s sleep"
    end
  end

  private

  def with_env(overrides)
    backup = overrides.keys.to_h { |key| [ key, ENV[key] ] }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    backup.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
