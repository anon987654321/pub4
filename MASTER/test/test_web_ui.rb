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
    segments = (1..3).map { |part| File.read(File.join(base, "face.part#{part}.txt")) }
    segments << File.read(File.join(base, "face_speech_runtime.js"))
    segments << File.read(File.join(base, "face_speech_playback.js"))
    segments << File.read(File.join(base, "face.part5.txt"))
    loader = File.read(File.join(base, "face.js"))
    (segments + [loader]).join("\n")
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
    assert_includes app_controller, 'before_action :enforce_tts_rate_limit, if: -> { controller_name == "tts" && action_in?(TTS_SYNTH_ACTIONS) }'
    assert_includes app_controller, "TTS_SYNTH_ACTIONS = %i[show].freeze"
    assert_includes app_controller, "TTS_POLL_ACTIONS = %i[status stream].freeze"
    assert_includes app_controller, "Retry-After"
  end

  def test_sensitive_web_actions_route_through_auth_pipeline
    app_controller = File.read(File.expand_path("../web/app/controllers/application_controller.rb", __dir__))

    assert_includes app_controller, "AUTHENTICATED_ACTIONS = %i["
    assert_includes app_controller, "dmesg history live metrics"
    assert_includes app_controller, "before_action :require_authenticated!, if: -> { action_in?(AUTHENTICATED_ACTIONS) }"
    assert_includes app_controller, 'master_tier != "authenticated"'
    assert_includes app_controller, 'render json: { error: "authentication required" }, status: :unauthorized'
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
    face_idx = index.rindex('asset_path("face.js")')
    refute_nil kernel_idx
    refute_nil face_idx
    assert_operator kernel_idx, :<, face_idx
    refute_includes index, '<link rel="prefetch" href="<%= asset_path("face.js") %>" as="script">'
    refute_match(/rel="modulepreload"[^>]+asset_path\("face\.js"\)/, index)
    # Boot modules ship through the compact javascript_include_tag(*%w[...]) manifest,
    # so they appear as bare (suffix-less) names, not "<name>.js".
    assert_includes index, "chat_actions"
    assert_includes index, "visual_bridge"
    assert_includes index, 'id="cognition-ecology"'
    assert_includes index, "cognition_ecology"
    assert_includes index, "cognition_ecology_render"
    assert_includes index, "visual_governor"
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

  def test_visual_bridge_delegates_event_classification_to_registry
    bridge = File.read(File.expand_path("../web/public/visual_bridge.js", __dir__))
    registry = File.read(File.expand_path("../web/public/topology_registry.js", __dir__))
    topologies = File.read(File.expand_path("../data/topologies.yml", __dir__))

    refute_includes bridge, "EVENT_MAP"
    assert_includes bridge, "MASTERTopology.classifyEvent"
    assert_includes registry, "phantom:detected"
    assert_includes topologies, "phantom:detected"
    assert_includes topologies, "infer:resolved|route:resolved|llm:routed"
  end

  def test_face_pauses_animation_loop_when_tab_hidden
    source = face_runtime_source

    assert_includes source, "ensureFrameLoop"
    assert_includes source, "frameLoopActive = false"
    assert_includes source, "dataset.hiddenTab"
  end

  def test_face_state_observer_does_not_watch_its_own_attribute_writes
    source = File.read(File.expand_path("../web/public/face_state.js", __dir__))

    # Regression: face_state.js's applyFrom() writes el.dataset.runtimeStatus on
    # the same elements observe() watches. Observing `attributes: true` there
    # re-fires the callback on every write -> an infinite mutation->observe->mutate
    # microtask loop that starves the main thread before load or the primer tap
    # handler ever runs (root cause behind 30+ "dead tap"/"slow page" commits,
    # fixed 2026-07-11). childList/characterData carry the real external signal.
    assert_includes source, "childList: true, subtree: true, characterData: true"
    refute_match(/observe\(el,\s*\{[^}]*attributes/, source)
  end

  def test_rc_d_master_digest_globs_all_face_modules
    rc = File.read(File.expand_path("../../OPENBSD/etc/rc.d/master", __dir__))

    # Regression: the precompile-skip digest once named ~10 face files
    # explicitly, so editing any of the ~30 other standalone face_*.js modules
    # (e.g. face_state.js) silently skipped precompile on restart and kept a
    # stale fingerprint live. The digest must glob face_*.js, not enumerate it.
    assert_includes rc, "face_*.js"
  end

  def test_primer_tap_unlocks_prompt_before_face_ready
    index = File.read(File.expand_path("../web/app/views/chat/index.html.erb", __dir__))
    css = File.read(File.expand_path("../web/public/face.css", __dir__))
    part5 = File.read(File.expand_path("../web/public/face.part5.txt", __dir__))

    assert_includes index, "dismissPrimer"
    assert_includes index, "revealPrompt"
    assert_includes index, "dismissPrimer();\n        revealPrompt();"
    assert_includes index, "z.classList.add('live')"
    assert_includes css, "#primer"
    assert_includes css, "z-index: var(--z-modal)"
    assert_includes css, "body:not(.face-ready) #zsh:not(.live)"
    assert_includes part5, "primerFired = true"
    assert_includes index, 'aria-describedby="primer-capabilities primer-consent"'
    assert_includes index, "Microphone access is requested only when you choose voice input"
    assert_includes index, "text remains available if graphics fail"
    assert_includes index, "if(e.key===' '||e.key==='Enter')"
    assert_includes index, "fallbackUi()"
    assert_includes css, "@media (prefers-reduced-motion: reduce)"
  end

  def test_command_palette_wired_in_chat_js
    source = File.read(File.expand_path("../web/public/chat.js", __dir__))

    assert_includes source, "wireCommandPalette"
    assert_includes source, "MASTERCommandPalette"
    assert_includes source, "cmd-palette"
  end

  def test_opencrabs_web_handlers_present
    chat = File.read(File.expand_path("../web/public/chat.js", __dir__))
    actions = File.read(File.expand_path("../web/public/chat_actions.js", __dir__))
    service = File.read(File.expand_path("../web/app/services/chat_service.rb", __dir__))
    dashboard = File.read(File.expand_path("../web/app/views/dashboard/index.html.erb", __dir__))

    assert_includes chat, "_chatOnCompaction"
    assert_includes chat, "_chatOnCtxFooter"
    assert_includes chat, "_chatOnPhantom"
    assert_includes chat, "/btw research"
    assert_includes chat, "/rebuild"
    assert_includes File.read(File.expand_path("../web/public/visual_bridge.js", __dir__)), "phantom:detected"
    assert_includes actions, "addEventListener('compaction'"
    assert_includes actions, "startsWith('!')"
    assert_includes service, "compaction:done"
    assert_includes service, "ctx:footer"
    assert_includes dashboard, "mission control"
    refute_includes dashboard, 'location.replace("/")'
  end

  def test_wave3_felt_sense_and_face_part5_wiring
    actions = File.read(File.expand_path("../web/public/chat_actions.js", __dir__))
    part5 = File.read(File.expand_path("../web/public/face.part5.txt", __dir__))
    service = File.read(File.expand_path("../web/app/services/chat_service.rb", __dir__))
    agent = File.read(File.expand_path("../lib/review/agent.rb", __dir__))
    index = File.read(File.expand_path("../web/app/views/chat/index.html.erb", __dir__))

    assert_includes actions, "window.collectFeltState = collectFeltState"
    assert_includes actions, "function collectFeltState()"
    assert_includes part5, "window.collectFeltState?.()"
    assert_includes part5, "addEventListener('compaction'"
    assert_includes part5, "addEventListener('ctx_footer'"
    assert_includes part5, "addEventListener('phantom'"
    assert_includes part5, "addEventListener('tool_stack'"
    assert_includes part5, "addEventListener('stage'"
    assert_includes part5, "addEventListener('btw'"
    assert_includes service, "felt_sense:"
    assert_includes service, '"felt:sense"'
    assert_includes agent, "felt_sense"
    assert_includes File.read(File.expand_path("../lib/review/agent/prompt_builder.rb", __dir__)), "felt_sense_section"
    assert_includes File.read(File.expand_path("../web/public/chat.js", __dir__)), "mood-sparkline"
  end

  def test_ui_backlog_wired
    chat = File.read(File.expand_path("../web/public/chat.js", __dir__))
    part5 = File.read(File.expand_path("../web/public/face.part5.txt", __dir__))
    index = File.read(File.expand_path("../web/app/views/chat/index.html.erb", __dir__))
    dashboard = File.read(File.expand_path("../web/app/views/dashboard/index.html.erb", __dir__))

    assert_includes chat, "wireUiBacklog"
    assert_includes chat, "MASTERLogSearch"
    assert_includes chat, "MASTERStreamMode"
    assert_includes chat, "collectJsonl"
    assert_includes part5, "dataset.inputDense"
    assert_includes part5, "sw:updated"
    assert_includes index, "skip-link"
    assert_includes index, "error-live"
    assert_includes index, "<textarea id=\"zin\""
    assert_includes dashboard, "context pressure"
    assert_includes dashboard, "repair queue"
  end

  def test_wave3_history_export_sparkline_wired
    chat = File.read(File.expand_path("../web/public/chat.js", __dir__))
    css = File.read(File.expand_path("../web/public/face.css", __dir__))

    assert_includes chat, "wireHistorySidebar"
    assert_includes chat, "MASTERHistory"
    assert_includes chat, "/chat/history"
    assert_includes chat, "wireSessionExport"
    assert_includes chat, "MASTERExport"
    assert_includes chat, "wireEmotionSparkline"
    assert_includes chat, "master:visual"
    assert_includes chat, "action: 'history'"
    assert_includes chat, "action: 'export'"
    assert_includes css, "#chat-history-panel"
    assert_includes css, "#history-list"
  end

  def test_ecology_render_pauses_when_tab_hidden
    source = File.read(File.expand_path("../web/public/cognition_ecology_render.js", __dir__))
    ecology = File.read(File.expand_path("../web/public/cognition_ecology.js", __dir__))
    css = File.read(File.expand_path("../web/public/face.css", __dir__))

    assert_includes source, "ecologyFrameActive = false"
    assert_includes source, "ensureEcologyFrame"
    assert_includes source, 'addEventListener("master:visual"'
    assert_includes ecology, "addEventListener(\"master:visual\""
    assert_includes ecology, "z-index:2"
    assert_match(/#cognition-ecology\s*\{[^}]*z-index:\s*2/m, css)
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
    assert_includes tts_controller, "voice_key, synth_style, rate, pitch = tts_voice_and_style(text)"
    assert_includes tts_controller, "def resolve_tts_style"
    assert_includes tts_controller, "Master::Voice::Speech.infer_style(text"
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
    assert_includes source, "async function ttsCacheKey(text, voice, style)"
    assert_includes source, "${style || 'auto'}"
  end

  def test_face_tts_priority_lanes_do_not_replay_from_generic_queue
    source = face_runtime_source

    assert_includes source, "function dropQueuedSpeech(text)"
    assert_includes source, "function nextQueuedSpeech()"
    assert_includes source, "dropQueuedSpeech(text)"
    assert_includes source, "const nextSpeech = nextQueuedSpeech()"
  end

  def test_face_tts_bridges_global_style_events
    bridge = File.read(File.expand_path("../web/public/visual_bridge.js", __dir__))
    speech = File.read(File.expand_path("../web/public/face_speech_runtime.js", __dir__))
    events = File.read(File.expand_path("../web/public/master_events.js", __dir__))

    assert_includes bridge, "new EventSource(\"/events/stream\")"
    assert_includes bridge, "type === \"tts:anticipate\""
    assert_includes bridge, "type === \"tts:style:active\""
    assert_includes bridge, "new CustomEvent(\"tts:style:active\""
    assert_includes bridge, "new CustomEvent(\"master:visual\""
    assert_includes speech, "tts:anticipate"
    assert_includes events, '"tts:style:active"'
    assert_includes events, '"tts:playback:start"'
    assert_includes events, '"tts:playback:end"'
    assert_includes events, '"tts:viseme"'
  end

  def test_face_tts_emits_lifecycle_and_viseme_events
    source = face_runtime_source

    assert_includes source, "function emitTtsEvent(type, detail = {})"
    assert_includes source, "emitTtsEvent('tts:playback:start'"
    assert_includes source, "emitTtsEvent('tts:playback:end'"
    assert_includes source, "emitTtsEvent('tts:viseme'"
    assert_includes source, "tts.current = text"
  end

  def test_face_semantics_routes_expression_through_blend_bridge_not_pools
    semantics = File.read(File.expand_path("../web/public/face_semantics.js", __dir__))
    bridge = File.read(File.expand_path("../web/public/face_blendshape_bridge.js", __dir__))

    refute_match(/mouthPool\.cells|eyePool\.cells/, semantics)
    assert_includes semantics, "MASTER_FACE_BLEND"
    assert_includes semantics, "FACE3D_ACTIVE"
    assert_includes bridge, "boostEye"
    assert_includes bridge, "applyPressure"
  end

  def test_face3d_consumes_tts_events_and_reports_nonblank_frames
    preview = File.read(File.expand_path("../web/public/face3d_preview.js", __dir__))
    renderer = File.read(File.expand_path("../web/public/face3d_renderer.js", __dir__))
    events = File.read(File.expand_path("../web/public/master_events.js", __dir__))

    assert_includes preview, 'addEventListener("tts:playback:start"'
    assert_includes preview, 'addEventListener("tts:viseme"'
    assert_includes preview, "engine.speakFrame"
    assert_includes preview, "face3d:nonblank"
    assert_includes preview, "FACE3D_ACTIVE"
    assert_includes preview, "bootFace3d"
    assert_includes renderer, "lastLitPixels"
    assert_includes events, '"face3d:nonblank"'
    part1 = File.read(File.expand_path("../web/public/face.part1.txt", __dir__))
    assert_includes part1, "face3d only"
    assert_includes part1, "_hasWebGL = false"
  end

  def test_public_asset_manifest_matches_source_files
    public_dir = File.expand_path("../web/public", __dir__)
    manifest_path = File.join(public_dir, "assets", ".manifest.json")
    skip "public asset manifest is absent; run Rails asset precompile to check drift" unless File.file?(manifest_path)

    index = File.read(File.expand_path("../web/app/views/chat/index.html.erb", __dir__))
    manifest = JSON.parse(File.read(manifest_path))
    boot_sources = boot_manifest_sources(index)

    boot_sources.each do |source|
      entry = manifest.fetch(source)
      source_path = File.join(public_dir, source)
      asset_path = File.join(public_dir, "assets", entry.fetch("digested_path"))

      assert File.file?(asset_path), "missing generated asset for #{source}"
      assert_equal File.read(source_path), File.read(asset_path), "generated asset drifted for #{source}"
    end
  end

  def boot_manifest_sources(index)
    include_block = index.match(/javascript_include_tag\(\*%w\[(.*?)\]/m)
    assert include_block, "chat index boot manifest not found"

    manifest_js = include_block[1].split.map { |name| "#{name}.js" }
    face_parts = index.scan(/face\.part\d+\.txt/).uniq.sort
    (manifest_js + %w[particle_kernel.js] + face_parts).uniq
  end

  def test_face_tts_audio_graph_uses_compressor_before_analyser
    source = face_runtime_source

    assert_includes source, "createDynamicsCompressor()"
    assert_includes source, "compressor.connect(analyser)"
    assert_includes source, "connectTTSAudio(audio"
  end

  def test_face_particles_are_crisp_depth_sized_pixels
    source = face_runtime_source

    assert_includes source, "let FACE_PIXEL_SIZE = 0.022"
    assert_includes source, "let FACE_GLOW_SCALE = 1.22"
    assert_includes source, "gl_PointSize=clamp"
    assert_includes source, "depth"
  end

  # SwarmCoordinator
  def test_swarm_coordinator_worker_roles
    # Just check the list is non-empty without booting real agents
    assert_includes Master::Review::Swarm::Coordinator::WORKER_CLASSES.keys, :analyst
    assert_includes Master::Review::Swarm::Coordinator::WORKER_CLASSES.keys, :coder
    assert_includes Master::Review::Swarm::Coordinator::WORKER_CLASSES.keys, :reviewer
    assert_includes Master::Review::Swarm::Coordinator::WORKER_CLASSES.keys, :researcher
  end

  def test_swarm_coordinator_unknown_role
    mock_agent = Minitest::Mock.new
    coord = Master::Review::Swarm::Coordinator.new(agent: mock_agent)
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
  def test_personality_default_is_anchor
    assert_equal :anchor, Master::Voice::Personality::DEFAULT
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
