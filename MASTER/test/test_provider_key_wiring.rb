# frozen_string_literal: true

require_relative "test_helper"
require "ruby_llm"

# providers.yml is the only source of API-key wiring, and two of its columns are
# claims about something outside this repository: `ruby_llm_key` names a setter
# on RubyLLM::Configuration, and `min_key_length` decides whether an env var
# counts as a key at all. Both were wrong at once on 2026-08-30 and the runtime
# did not boot: `agy` — the Antigravity CLI, which is not a RubyLLM provider —
# declared `ruby_llm_key: agy_api_key` with `min_key_length: 0`, so the unset
# AGY_BIN satisfied `"".length >= 0` and RubyLLM.configure raised NoMethodError
# on every single boot. `bin/pub4 gate` reported it as a failed lexical stage
# with the stack trace of a scan that had never started.
#
# These tests read the gem rather than restating what it offers, so a ruby_llm
# upgrade that renames or drops a setter fails here and names the provider.
class TestProviderKeyWiring < Minitest::Test
  def setup
    @config = RubyLLM::Configuration.new
  end

  def test_every_declared_ruby_llm_key_has_a_setter_on_the_installed_gem
    missing = Master.api_key_specs.reject { |attribute, _env, _min| @config.respond_to?("#{attribute}=") }

    assert_empty missing.map(&:first).uniq,
                 "providers.yml names ruby_llm_key values RubyLLM #{RubyLLM::VERSION} has no setter for"
  end

  # The detector above is only worth trusting if it can still fail.
  def test_the_setter_check_still_detects_a_bad_key
    refute_respond_to @config, :not_a_provider_api_key=
  end

  def test_an_unset_env_var_is_not_a_key_however_low_the_minimum
    ENV.delete("MASTER_TEST_ABSENT_KEY")
    stubbed_specs = [[:openai_api_key, "MASTER_TEST_ABSENT_KEY", 0]]

    Master.stub(:api_key_specs, ->(**_kwargs) { stubbed_specs }) do
      refute Master.api_key_present?("MASTER_TEST_ABSENT_KEY"),
             "an unset env var reports present at minimum 0"
    end
  end

  def test_any_api_key_present_can_return_false
    stubbed_specs = [[:openai_api_key, "MASTER_TEST_ABSENT_KEY", 0]]

    ENV.delete("MASTER_TEST_ABSENT_KEY")
    Master.stub(:api_key_specs, stubbed_specs) do
      Master.stub(:agy_cli_available?, false) do
        refute Master.any_api_key_present?
      end
    end
  end

  # A providers.yml row for a provider this gem version does not know must not
  # take the runtime down with it.
  def test_an_unknown_ruby_llm_key_is_skipped_rather_than_raised
    ENV["MASTER_TEST_UNKNOWN_KEY"] = "x" * 40
    stubbed_specs = [[:definitely_not_a_ruby_llm_api_key, "MASTER_TEST_UNKNOWN_KEY", 20]]

    Master.stub(:api_key_specs, stubbed_specs) do
      _out, err = capture_io { Master.send(:apply_api_keys, @config) }

      assert_match(/MASTER_TEST_UNKNOWN_KEY/, err, "the skipped key should be named, not swallowed")
    end
  ensure
    ENV.delete("MASTER_TEST_UNKNOWN_KEY")
  end
end
