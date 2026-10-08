# frozen_string_literal: true

require_relative "test_helper"

class TestRuntimeRegexpTimeout < Minitest::Test
  def test_runtime_installs_a_configurable_regexp_timeout
    previous_timeout = Regexp.timeout
    previous_env = ENV["MASTER_REGEXP_TIMEOUT"]
    ENV["MASTER_REGEXP_TIMEOUT"] = "0.25"

    Master.send(:install_regexp_timeout!)

    assert_in_delta 0.25, Regexp.timeout, 0.001
  ensure
    previous_env.nil? ? ENV.delete("MASTER_REGEXP_TIMEOUT") : ENV["MASTER_REGEXP_TIMEOUT"] = previous_env
    Regexp.timeout = previous_timeout
  end

  def test_invalid_timeout_falls_back_to_the_runtime_default
    previous_timeout = Regexp.timeout
    previous_env = ENV["MASTER_REGEXP_TIMEOUT"]
    ENV["MASTER_REGEXP_TIMEOUT"] = "not-a-number"

    Master.send(:install_regexp_timeout!)

    assert_in_delta Master::MasterRuntime::REGEXP_TIMEOUT_S, Regexp.timeout, 0.001
  ensure
    previous_env.nil? ? ENV.delete("MASTER_REGEXP_TIMEOUT") : ENV["MASTER_REGEXP_TIMEOUT"] = previous_env
    Regexp.timeout = previous_timeout
  end

  def test_pathological_regexp_is_interrupted
    previous_timeout = Regexp.timeout
    Regexp.timeout = 0.01

    error = assert_raises(Regexp::TimeoutError) do
      /^(a|a)+$/.match?("a" * 100_000 + "x")
    end

    assert_kind_of Regexp::TimeoutError, error
  ensure
    Regexp.timeout = previous_timeout
  end
end
