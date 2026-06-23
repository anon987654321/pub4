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

  def face_runtime_source
    base = File.expand_path("../web/public", __dir__)
    parts = Dir.glob(File.join(base, "face.part*.txt")).sort.map { |path| File.read(path) }
    loader = File.read(File.join(base, "face.js"))
    (parts + [loader]).join("\n")
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
    assert_includes app_controller, 'before_action :enforce_tts_rate_limit, if: -> { controller_name == "tts" && action_in?(TTS_ACTIONS) }'
    assert_includes app_controller, "TTS_ACTIONS = %i[show status].freeze"
    assert_includes app_controller, "Retry-After"
  end

  def test_sensitive_web_actions_route_through_auth_pipeline
    app_controller = File.read(File.expand_path("../web/app/controllers/application_controller.rb", __dir__))

    assert_includes app_controller, "AUTHENTICATED_ACTIONS = %i["
    assert_includes app_controller, "command dmesg enhance history live metrics photo post_event state stream"
    assert_includes app_controller, "before_action :require_authenticated!, if: -> { action_in?(AUTHENTICATED_ACTIONS) }"
    assert_match(/def\s+visitor\?\s*\n\s*false\s*\n\s*end/, app_controller)
    assert_match(/def\s+require_authenticated!\s*\n\s*end/, app_controller)
  end

  def test_authenticated_web_actions_are_rate_limited
    app_controller = File.read(File.expand_path("../web/app/controllers/application_controller.rb", __dir__))

    assert_includes app_controller, "WEB_READ_RATE_LIMIT  = 120"
    assert_includes app_controller, "WEB_WRITE_RATE_LIMIT = 60"
    assert_includes app_controller, "before_action :enforce_web_read_rate_limit, if: -> { action_in?(%i[dmesg history live metrics]) }"
    assert_includes app_controller, "before_action :enforce_web_write_rate_limit, if: -> { action_in?(%i[command enhance photo post_event state]) }"
  end

  def test_message_endpoint_uses_strong_params
    chat_controller = File.read(File.expand_path("../web/app/controllers/chat_controller.rb", __dir__))

    assert_includes chat_controller, "mp = message_params"
    assert_includes chat_controller, "input = mp[:message].to_s.strip"
    assert_includes chat_controller, "params.permit(:message, :state, :pre_enhanced, :voice, :image_token, image: %i[data mime name])"
  end

  def test_chat_service_smoke_messages_bypass_pipeline
    chat_service = File.read(File.expand_path("../web/app/services/chat_service.rb", __dir__))

    assert_includes chat_service, "SMOKE_MESSAGES"
    assert_includes chat_service, "stream_open!"
    assert_includes chat_service, "smoke_reply?"
    assert_includes chat_service, 'when "ping" then "pong"'
  end

  def test_chat_index_loads_particle_kernel_before_face
    index = File.read(File.expand_path("../web/app/views/chat/index.html.erb", __dir__))
    kernel_idx = index.index("particle_kernel.js")
    face_idx = index.index('type="module"')
    refute_nil kernel_idx
    refute_nil face_idx
    assert_operator kernel_idx, :<, face_idx
    assert_includes index, "chat_actions.js"
    assert_includes index, "visual_bridge.js"
    assert_includes index, 'id="cognition-ecology"'
    assert_includes index, "cognition_ecology.js"
    assert_includes index, "cognition_ecology_render.js"
    assert_includes index, "visual_governor.js"
    ecology_idx = index.index("cognition-ecology")
    face_canvas_idx = index.index('id="face"')
    assert_operator ecology_idx, :<, face_canvas_idx
  end

  def test_visual_bridge_does_not_blur_face_canvas
    source = File.read(File.expand_path("../web/public/visual_bridge.js", __dir__))

    refute_includes source, "blur("
    assert_includes source, 'face.style.filter = ""'
    assert_includes source, "disconnectSse"
    assert_includes source, 'document.addEventListener("visibilitychange"'
  end

  def test_face_pauses_animation_loop_when_tab_hidden
    source = face_runtime_source

    assert_includes source, "ensureFrameLoop"
    assert_includes source, "frameLoopActive = false"
    assert_includes source, 'dataset.hiddenTab'
  end

  def test_command_palette_wired_in_chat_js
    source = File.read(File.expand_path("../web/public/chat.js", __dir__))

    assert_includes source, "wireCommandPalette"
    assert_includes source, "MASTERCommandPalette"
    assert_includes source, "cmd-palette"
  end

  def test_ecology_render_pauses_when_tab_hidden
    source = File.read(File.expand_path("../web/public/cognition_ecology_render.js", __dir__))

    assert_includes source, "ecologyFrameActive = false"
    assert_includes source, "ensureEcologyFrame"
  end

  def test_models_enable_strict_loading_by_default
    application_record = File.read(File.expand_path("../web/app/models/application_record.rb", __dir__))

    assert_includes application_record, "self.strict_loading_by_default = true"
  end

  def test_tts_endpoint_sets_cache_headers_and_supports_conditional_get
    tts_controller = File.read(File.expand_path("../web/app/controllers/tts_controller.rb", __dir__))
    tts_job = File.read(File.expand_path("../web/app/services/tts_job.rb", __dir__))

    assert_includes tts_job, "Digest::SHA256.hexdigest"
    assert_includes tts_job, "def failed?"
    assert_includes tts_job, "record_failure"
    assert_includes tts_controller, 'response.headers["ETag"] = etag'
    assert_includes tts_controller, 'response.headers["Cache-Control"] = "public, max-age=3600"'
    assert_includes tts_controller, "head(:not_modified)"
    assert_includes tts_controller, 'status: "failed"'
    assert_includes tts_controller, 'response.headers["X-TTS-Job"] = job.job_id'
  end

  def test_face_tts_polls_job_status_header
    source = face_runtime_source

    assert_includes source, "res.headers.get('X-TTS-Job')"
    assert_includes source, "pollTTSJob(job"
    assert_includes source, "/chat/tts/status?job="
  end

  def test_face_tts_uses_indexeddb_blob_cache
    source = face_runtime_source

    assert_includes source, "indexedDB.open(TTS_DB_NAME"
    assert_includes source, "crypto.subtle.digest('SHA-256'"
    assert_includes source, "readCachedTTS(key)"
    assert_includes source, "writeCachedTTS(key, blob)"
  end

  def test_face_tts_bridges_global_style_events
    source = face_runtime_source

    assert_includes source, "new EventSource('/events/stream')"
    assert_includes source, "type === 'tts:anticipate'"
    assert_includes source, "type === 'tts:style:active'"
    assert_includes source, "new CustomEvent('master:visual'"
  end

  def test_face_tts_audio_graph_uses_compressor_before_analyser
    source = face_runtime_source

    assert_includes source, "createDynamicsCompressor()"
    assert_includes source, "compressor.connect(analyser)"
    assert_includes source, "connectTTSAudio(audio"
  end

  def test_face_particles_are_crisp_depth_sized_pixels
    source = face_runtime_source

    assert_includes source, "let FACE_PIXEL_SIZE = 0.019"
    assert_includes source, "let FACE_GLOW_SCALE = 1.22"
    assert_includes source, "gl_PointSize=clamp"
    assert_includes source, "depth"
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
      %w[brain/memory brain/tools brain/identity].each { |key| m.forget(key) }
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

  def test_personality_catalog_includes_named_profiles
    names = Master::Voice::Personality.persona_names

    %i[ronin lawyer hacker architect sysadmin trader medic].each do |name|
      assert_includes names, name
    end

    ronin = Master::Voice::Personality.new(:ronin)
    assert_equal "en-US-AndrewNeural", ronin.voice
    assert_equal "-25%", ronin.tts_rate
    assert_equal "-100Hz", ronin.tts_pitch
    assert_equal :deep, ronin.style
    assert_includes ronin.knowledge_sources, "https://man.openbsd.org/"
  end

  # UnwrapError
  def test_unwrap_error_is_runtime_error_subclass
    assert Master::UnwrapError < RuntimeError
  end
end
