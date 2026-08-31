# frozen_string_literal: true

require_relative "test_helper"
require_relative "support_fake_config"

# agy is the only entry in the routing tables that is not an API model. It is
# the Antigravity CLI, reached by executing a binary, and two things about it
# have to stay true no matter how the tiers are ordered:
#
#   1. It is never offered when the binary is not there. An id that can only be
#      failed over is not a route.
#   2. It does not outrank a configured API key. A key is a paid, health-checked
#      lane; the CLI answers "quota reached" when its subscription is spent, and
#      a dead lane at the head of the chain stalls every LLM-backed rule.
#
# Both were broken at once on 2026-08-31, in opposite directions, and the fixes
# came from two sessions working in the same hour. The second is held by
# data/models.yml, which no longer prepends the agy anchors to any tier, and by
# default_model / primary_models / AuthProfileLane#models_for_router leading
# with a key. The first now falls out of the same change — measured, not
# assumed: with every code-side agy filter removed, the two absence assertions
# below still pass, which is why this file holds the property and no code
# carries a second guard for it.
#
# The shape this hid behind: MASTER_NO_AGY_CLI existed and both
# agy_cli_available? methods honoured it, so the guard looked complete while the
# ids arrived by paths that never asked. test_keyless_routing.rb neutralises
# both CLIs for the same reason; this file is where agy's own routing is graded.
class TestAgyReachability < Minitest::Test
  FakeConfig = Master::TestSupport::FakeConfig
  GUARDED = %w[
    XAI_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
    DEEPSEEK_API_KEY GOOGLE_API_KEY GEMINI_API_KEY MISTRAL_API_KEY
    MASTER_KEYLESS MASTER_WEB_CHAT MASTER_NO_CLAUDE_CLI MASTER_NO_AGY_CLI AGY_BIN
  ].freeze
  OPENROUTER_KEY = "sk-or-v1-#{"a" * 64}"
  AGY = /\Aagy(?::|\z)/

  def setup
    @saved = GUARDED.to_h { |key| [key, ENV[key]] }
    GUARDED.each { |key| ENV.delete(key) }
    ENV["MASTER_NO_CLAUDE_CLI"] = "1"
  end

  def teardown
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
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

  def chain
    router.fallback_chain(task_type: :exploration)
  end

  # --- 1. never offered when the binary is absent --------------------------

  def test_default_model_does_not_name_agy_when_the_binary_is_absent
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(false) do
      refute_match AGY, Master.default_model,
                   "default_model named the Antigravity CLI on a machine that has no agy binary"
    end
  end

  def test_the_fallback_chain_offers_no_agy_when_the_binary_is_absent
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(false) do
      offered = chain

      assert_empty offered.grep(AGY), "the chain offered agy models on a machine with no agy binary"
      refute_empty offered, "dropping agy emptied the chain"
    end
  end

  # The same with no key at all, since that is the path where agy is the
  # intended answer and so the one most likely to hand back an absent binary.
  def test_nothing_names_agy_with_neither_a_key_nor_a_binary
    with_agy(false) do
      refute_match AGY, Master.default_model
      assert_empty chain.grep(AGY)
    end
  end

  # --- 2. present, but behind a configured key -----------------------------

  def test_agy_is_the_default_when_it_is_there_and_no_key_is
    with_agy(true) do
      assert_match AGY, Master.default_model,
                   "with no API key and the binary present, agy is the route that exists"
    end
  end

  def test_a_configured_key_outranks_agy
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(true) do
      refute_match AGY, Master.default_model,
                   "a paid, health-checked key lost to a CLI whose subscription may be spent"
      refute_match AGY, chain.first,
                   "agy led the fallback chain while a configured key was available"
    end
  end

  # Behind the key is not the same as gone: a spent key must still fail over to
  # the CLI that is installed.
  def test_agy_is_still_offered_behind_the_key
    ENV["OPENROUTER_API_KEY"] = OPENROUTER_KEY
    with_agy(true) do
      refute_empty chain.grep(AGY), "agy was dropped from the chain rather than ranked below the key"
    end
  end

  # --- the instrument itself ----------------------------------------------

  # Every assertion above rests on the stub being taken for a real binary. If
  # that stopped working, the absence half would pass for the wrong reason.
  def test_the_stub_is_actually_detected
    with_agy(true) { assert Master.agy_cli_available?, "the agy stub was not detected as available" }
    with_agy(false) { refute Master.agy_cli_available? }
  end
end
