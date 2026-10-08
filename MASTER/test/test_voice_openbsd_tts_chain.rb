# frozen_string_literal: true

require_relative "test_helper"

class TestOpenbsdTtsChain < Minitest::Test
  def test_openbsd_chain_constant_excludes_local_mlx
    chain = Master::Voice::Engines::OPENBSD_CHAIN
    assert_includes chain, "replicate_kokoro"
    refute_includes chain, "mlx"
    refute_includes chain, "chatterbox"
  end

  # No token from anywhere load_token looks: REPLICATE_API_TOKEN,
  # REPLICATE_API_KEY and the config file. Clearing one variable left the
  # other two to the machine running the suite.
  def test_attempt_replicate_on_openbsd_without_token
    engines = Master::Voice::Engines
    Master::Io::ReplicateClient.stub(:load_token, "") do
      engines.stub(:openbsd?, true) do
        refute engines.available?("replicate_kokoro", {})
        assert engines.attempt?("replicate_kokoro", {})
      end
    end
  end

  def test_load_config_honors_master_tts_engine_chain_override
    prior = ENV["MASTER_TTS_ENGINE_CHAIN"]
    ENV["MASTER_TTS_ENGINE_CHAIN"] = "replicate_kokoro,edge"
    engines = Master::Voice::Engines
    engines.stub(:openbsd?, true) do
      cfg = Master::Voice::Transcendent.load_config
      assert_equal "replicate_kokoro,edge", cfg["engine_chain"]
    end
  ensure
    prior.nil? ? ENV.delete("MASTER_TTS_ENGINE_CHAIN") : ENV["MASTER_TTS_ENGINE_CHAIN"] = prior
  end
end
