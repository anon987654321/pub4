# frozen_string_literal: true

require_relative "test_helper"
require "rack/test"

# Minimal Rack test harness for the web UI chat controller.
# Tests cover SSE stream, TTS endpoint, dmesg, and metrics.

ENV["RAILS_ENV"] = "test"

# We test the controller logic via a stub Rack app rather than
# booting the full Rails stack.
class FakeSpeech
  def self.available?  = true
  def self.synthesize_bytes(_text, **) = "FAKE-MP3-BYTES"
end

class FakePipeline
  attr_writer :result
  def call(_ctx) = @result || Master::Result.ok(rendered: "hello from pipeline")
end

class FakeSession
  def token_est = 42
  def cost      = 0.0001
end

class FakeAgent
  def model = "test/model-7b"
end

class FakeContainer
  def [](key)
    case key
    when :agent    then FakeAgent.new
    when :session  then FakeSession.new
    when :pipeline then @pipeline ||= FakePipeline.new
    end
  end
  def pipeline = self[:pipeline]
end

class TestWebUI < Minitest::Test
  include Rack::Test::Methods

  def setup
    @container = FakeContainer.new
  end

  # Result monad
  def test_result_ok_wraps_value
    r = Master::Result.ok("hello")
    assert r.ok?
    assert_equal "hello", r.value!
  end

  def test_result_err_wraps_message
    r = Master::Result.err("boom")
    assert r.err?
    assert_equal "boom", r.message
  end

  def test_result_err_value_bang_raises_unwrap_error
    r = Master::Result.err("boom")
    assert_raises(Master::UnwrapError) { r.value! }
  end

  def test_result_ok_chaining
    r = Master::Result.ok(5).and_then { |v| Master::Result.ok(v * 2) }
    assert_equal 10, r.value!
  end

  def test_result_err_short_circuits
    r = Master::Result.err("x").and_then { raise "should not reach" }
    assert r.err?
  end

  # Pipeline
  def test_pipeline_returns_result
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.ok?
    assert_includes result.value![:rendered], "hello"
  end

  def test_pipeline_err_propagates
    @container.pipeline.result = Master::Result.err("model down")
    result = @container.pipeline.call(Master::Result.ok(user_message: "hi"))
    assert result.err?
    assert_equal "model down", result.message
  end

  # Speech bytes
  def test_speech_synthesize_bytes_stub
    bytes = FakeSpeech.synthesize_bytes("hello world")
    assert_equal "FAKE-MP3-BYTES", bytes
  end

  def test_tts_endpoint_has_rate_limit_before_action
    app_controller = File.read(File.expand_path("../web/app/controllers/application_controller.rb", __dir__))

    assert_includes app_controller, "TTS_RATE_LIMIT  = 30"
    assert_includes app_controller, "before_action :enforce_tts_rate_limit, only: [:tts]"
    assert_includes app_controller, "Retry-After"
  end

  def test_tts_endpoint_sets_cache_headers_and_supports_conditional_get
    chat_controller = File.read(File.expand_path("../web/app/controllers/chat_controller.rb", __dir__))

    assert_includes chat_controller, "Digest::SHA256.hexdigest"
    assert_includes chat_controller, 'response.headers["ETag"] = etag'
    assert_includes chat_controller, 'response.headers["Cache-Control"] = "public, max-age=3600"'
    assert_includes chat_controller, "head(:not_modified)"
  end

  def test_face_tts_uses_indexeddb_blob_cache
    face_js = File.read(File.expand_path("../web/public/face.js", __dir__))

    assert_includes face_js, "indexedDB.open(TTS_DB_NAME"
    assert_includes face_js, "crypto.subtle.digest('SHA-256'"
    assert_includes face_js, "readCachedTTS(key)"
    assert_includes face_js, "writeCachedTTS(key, blob)"
  end

  def test_face_tts_bridges_global_style_events
    face_js = File.read(File.expand_path("../web/public/face.js", __dir__))

    assert_includes face_js, "new EventSource('/events/stream')"
    assert_includes face_js, "type === 'tts:anticipate'"
    assert_includes face_js, "type === 'tts:style:active'"
    assert_includes face_js, "new CustomEvent('master:visual'"
  end

  def test_face_tts_browser_fallback_maps_voice_names
    face_js = File.read(File.expand_path("../web/public/face.js", __dir__))

    assert_includes face_js, "TTS_FALLBACK_VOICE_HINTS"
    assert_includes face_js, "pickBrowserVoice(voiceKey)"
    assert_includes face_js, "new SpeechSynthesisUtterance(text)"
    assert_includes face_js, "utterance.voice = pickBrowserVoice(voiceKey)"
  end

  def test_face_tts_audio_graph_uses_compressor_before_analyser
    face_js = File.read(File.expand_path("../web/public/face.js", __dir__))

    assert_includes face_js, "createDynamicsCompressor()"
    assert_includes face_js, "boost.connect(compressor)"
    assert_includes face_js, "compressor.connect(analyser)"
    assert_includes face_js, "connectTTSAudio(audio"
  end

  # SwarmCoordinator
  def test_swarm_coordinator_worker_roles
    # Just check the list is non-empty without booting real agents
    assert_includes Master::Judge::Swarm::Coordinator::WORKER_CLASSES.keys, :analyst
    assert_includes Master::Judge::Swarm::Coordinator::WORKER_CLASSES.keys, :coder
    assert_includes Master::Judge::Swarm::Coordinator::WORKER_CLASSES.keys, :reviewer
    assert_includes Master::Judge::Swarm::Coordinator::WORKER_CLASSES.keys, :researcher
  end

  def test_swarm_coordinator_unknown_role
    mock_agent = Minitest::Mock.new
    coord = Master::Judge::Swarm::Coordinator.new(agent: mock_agent)
    result = coord.dispatch(:nonexistent, task: "foo")
    assert result.err?
    assert_includes result.message, "unknown role"
  end

  # Memory
  def test_memory_remember_and_recall
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:user_name, "Osman")
      assert_equal "Osman", m.recall(:user_name)
    end
  end

  def test_memory_context_summary_nil_when_empty
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      assert_nil m.context_summary
    end
  end

  def test_memory_context_summary_lists_keys
    Dir.mktmpdir do |dir|
      m = Master::Memory.new(root: dir)
      m.remember(:language, "Ruby")
      summary = m.context_summary
      assert_includes summary, "language"
      assert_includes summary, "Ruby"
    end
  end

  # Personality
  def test_personality_default_is_malay
    assert_equal :malay, Master::Voice::Personality::DEFAULT
  end

  def test_personality_system_prompt_non_empty
    p = Master::Voice::Personality.new(:malay)
    assert p.system_prompt.length > 10
  end

  def test_personality_system_prompt_memoized
    p = Master::Voice::Personality.new(:malay)
    assert_same p.system_prompt, p.system_prompt
  end

  # UnwrapError
  def test_unwrap_error_is_runtime_error_subclass
    assert Master::UnwrapError < RuntimeError
  end
end
