# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"

# agy is the only entry in the routing tables that is not an API model. It is
# the Antigravity CLI, reached by executing a binary, and `models.grok_primary`
# leads with it — so every table that hands out ids from that pool has to ask
# whether the binary is there, and two of them did not.
#
# The shape this hid behind: `MASTER_NO_AGY_CLI` existed and was honoured by
# both `agy_cli_available?` methods, so the guard looked complete. The ids
# reached the fallback chain and `default_model` by a different path, where
# nothing asked. On a machine with no agy binary the chain led with `agy:auto`
# and had to fail the call before it could route; on a machine with one, every
# assertion in test_keyless_routing.rb about having no provider failed instead.
# Both directions are pinned here, because a reachability check that only ever
# runs one way is the half of this that was already true.
class TestAgyReachability < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig
  GUARDED = %w[
    XAI_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
    DEEPSEEK_API_KEY GOOGLE_API_KEY GEMINI_API_KEY MISTRAL_API_KEY
    MASTER_KEYLESS MASTER_WEB_CHAT MASTER_NO_CLAUDE_CLI MASTER_NO_AGY_CLI AGY_BIN
  ].freeze

  def setup
    @saved = GUARDED.to_h { |key| [key, ENV[key]] }
    GUARDED.each { |key| ENV.delete(key) }
    ENV["MASTER_NO_CLAUDE_CLI"] = "1"
    Master.instance_variable_set(:@grok_primary_ids, nil)
  end

  def teardown
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    Master.instance_variable_set(:@grok_primary_ids, nil)
  end

  # The tables still lead with agy, which is the point of the fix: it is skipped
  # for being unreachable, never for being unwanted.
  def test_the_pool_still_leads_with_agy_when_the_binary_is_there
    assert_match(/\Aagy/, agy_pool.first,
                 "models.grok_primary no longer leads with agy — this file's premise is stale")
  end

  def agy_pool
    Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
          .dig("models", "grok_primary").map { |model| model["id"] }
  end

  def with_agy(available)
    if available
      # A file that exists and is executable is what both lookups accept, and
      # AGY_BIN is the first thing either of them reads.
      ENV.delete("MASTER_NO_AGY_CLI")
      ENV["AGY_BIN"] = agy_stub
    else
      ENV["MASTER_NO_AGY_CLI"] = "1"
    end
    yield
  end

  def agy_stub
    @agy_stub ||= begin
      path = File.join(Dir.mktmpdir("agy"), "agy")
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
      path
    end
  end

  def router
    Master::CLI::Routing::ModelRouter.new(config: FakeConfig.new(model: "x"), root: Master::ROOT)
  end

  # --- default_model -------------------------------------------------------

  def test_default_model_does_not_name_agy_when_the_binary_is_absent
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{"a" * 64}"
    with_agy(false) do
      refute_match(/\Aagy/, Master.default_model,
                   "default_model named the Antigravity CLI on a machine that has no agy binary")
    end
  end

  def test_default_model_names_agy_when_the_binary_is_present
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{"a" * 64}"
    with_agy(true) do
      assert_match(/\Aagy/, Master.default_model)
    end
  end

  # --- the router's fallback chain ----------------------------------------

  def test_the_fallback_chain_drops_agy_when_the_binary_is_absent
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{"a" * 64}"
    with_agy(false) do
      chain = router.fallback_chain(task_type: :exploration)

      assert_empty chain.grep(/\Aagy(?::|\z)/),
                   "the chain offered agy models on a machine with no agy binary"
      refute_empty chain, "dropping agy emptied the chain"
    end
  end

  def test_the_fallback_chain_leads_with_agy_when_the_binary_is_present
    ENV["OPENROUTER_API_KEY"] = "sk-or-v1-#{"a" * 64}"
    with_agy(true) do
      assert_match(/\Aagy/, router.fallback_chain(task_type: :exploration).first)
    end
  end
end
