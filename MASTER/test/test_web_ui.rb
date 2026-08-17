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
    # Boot modules are declared in web/config/face_assets.yml and rendered from
    # it; the view no longer names them, so assert against the manifest.
    manifest = YAML.safe_load_file(File.expand_path("../web/config/face_assets.yml", __dir__))
    %w[chat_actions visual_bridge visual_governor].each do |name|
      assert_includes manifest["shell_manifest"], name
    end
    %w[cognition_ecology.js cognition_ecology_render.js].each do |name|
      assert_includes manifest["face_vision_deferred"], name
    end
    assert_includes index, 'id="cognition-ecology"'
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

  def test_rc_d_master_digest_covers_every_manifest_asset
    rc = File.read(File.expand_path("../../OPENBSD/etc/rc.d/master", __dir__))

    # Regression: the precompile-skip digest named its inputs by hand, so
    # editing a face asset it did not list silently skipped precompile on
    # restart and kept a stale fingerprint live. A face_*.js glob fixed that for
    # the face_-prefixed half and left 15 of 38 uncovered — among them
    # particle_kernel.js, face.runtime.js and three.face.module.js. It now reads
    # web/config/face_assets.yml, so a new module is covered when it is declared.
    assert_includes rc, "script/face_asset_paths.rb"
    assert_includes rc, "cksum $_face_assets"
  end

  def test_face_asset_paths_script_emits_every_declared_asset
    web = File.expand_path("../web", __dir__)
    manifest = YAML.safe_load_file(File.join(web, "config", "face_assets.yml"))
    declared = %w[face_eager face_runtime_deferred face_vision_deferred shell_blocking shell_early shell_late]
               .flat_map { |group| Array(manifest[group]) }
    declared += manifest.fetch("singletons").values
    declared += Array(manifest["shell_manifest"]).map { |name| "#{name}.js" }

    emitted = `#{RbConfig.ruby} #{File.join(web, "script", "face_asset_paths.rb")}`.lines.map { |l| File.basename(l.strip) }

    assert_equal declared.uniq.sort, emitted.sort
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
    # The consent sentence is the one thing on the primer a visitor has to be
    # able to read before deciding to tap, so it is pinned by content and not
    # only by presence. Through the key, because the template now localises it —
    # the literal spelling would fail on a view that had got more correct.
    assert_localised_copy index, "face.primer_consent",
                          "Starts visuals and sound. Microphone access is requested only when " \
                          "you choose voice input; text remains available if graphics fail."
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
    assert_localised_copy dashboard, "dashboard.heading_mission", "mission control"
    refute_includes dashboard, 'location.replace("/")'
  end

  # The dashboard renders through I18n, so asserting the English string against
  # the template only passed until the view was localised — it then failed on a
  # view that was more correct, not less. Pin the key in the template and the
  # copy in the locale file, so the assertion survives a second locale and still
  # says which words the panel is meant to show.
  def assert_localised_copy(template, key, english)
    assert_includes template, %(t("#{key}"))
    locale = YAML.safe_load_file(File.expand_path("../web/config/locales/en.yml", __dir__))
    value = key.split(".").reduce(locale.fetch("en")) { |node, segment| node.fetch(segment) }
    assert_equal english, value, "en.yml #{key} drifted from the copy this page promises"
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
    # The mood sparkline used to be asserted here too. It was the visible end of
    # this chain and it is gone (see test_no_corner_hud_readouts_return); the
    # felt-sense wiring above it is what this test is actually for.
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
    assert_localised_copy dashboard, "dashboard.panels.pressure", "context pressure"
    assert_localised_copy dashboard, "dashboard.panels.repair", "repair queue"
  end

  def test_wave3_history_and_export_wired
    chat = File.read(File.expand_path("../web/public/chat.js", __dir__))
    css = File.read(File.expand_path("../web/public/face.css", __dir__))

    assert_includes chat, "wireHistorySidebar"
    assert_includes chat, "MASTERHistory"
    assert_includes chat, "/chat/history"
    assert_includes chat, "wireSessionExport"
    assert_includes chat, "MASTERExport"
    assert_includes chat, "master:visual"
    assert_includes chat, "action: 'history'"
    assert_includes chat, "action: 'export'"
    assert_includes css, "#chat-history-panel"
    assert_includes css, "#history-list"
  end

  # The corners stay empty.
  #
  # Two HUD readouts sat in them and were removed on 2026-08-14 at the operator's
  # request: #brutalist-strip, a <pre> in the top-left printing "mode=idle H=0.42
  # C=0.88", and #mood-sparkline, a row of <i> bars flush beside the mic icon
  # (pinned 22px in from the right against the mic's 2px).
  #
  # Four separate files created or rendered them — chat.js, face.part1.txt,
  # face_speech_runtime.js and face_vision_c.js for the sparkline, face_brutalist.js
  # for the strip — and each would have put it back on its own, since every one
  # creates the element if it is missing. That is why this asserts across the whole
  # served tree rather than one file: removing three of four leaves the HUD on
  # screen and the diff looking done.
  #
  # public/assets/ is excluded: it is precompiled output, gitignored, and
  # regenerated from these sources.
  def test_no_corner_hud_readouts_return
    root = File.expand_path("../web/public", __dir__)
    sources = Dir[File.join(root, "*.js"), File.join(root, "*.css"), File.join(root, "*.txt")]
              .reject { |path| path.include?("/assets/") }

    offenders = sources.select do |path|
      File.read(path, encoding: "UTF-8").match?(/mood-sparkline|brutalist-strip/)
    end.map { |path| File.basename(path) }

    assert_empty offenders,
                 "a corner HUD readout is back. Every one of these files creates the element if it is " \
                 "absent, so one is enough to put it on screen: #{offenders.join(', ')}"
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

  # NOTE: the legacy face3d_preview.js/face3d_renderer.js WebGL-overlay pair
  # this test used to cover was deliberately removed in 6f186797 ("MASTER/web:
  # remove legacy face3d (Papua-mask) overlay, port homo_futura geometry") --
  # it was a footgun 2D-canvas painter that could permanently block the real
  # WebGL face by grabbing the shared #face canvas context. face3d:nonblank
  # is gone from master_events.js and "face3d only"/"_hasWebGL = false" are
  # gone from face.part1.txt too; nothing here still applies. See also
  # test_face_semantics_routes_expression_through_blend_bridge_not_pools for
  # the one intentionally-remaining FACE3D_ACTIVE reference (a harmless dead
  # flag check in face_semantics.js the removal commit chose to leave).

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

  # A template literal followed immediately by "(" calls the resulting string,
  # which is a TypeError every time that line runs. It parses, so `node --check`
  # and every syntax gate pass it.
  #
  # This is not hypothetical: e7e48eed1's mechanical sweep ("template_literals"
  # among the AstFixer autofixes it names) rewrote four working concatenations
  # into exactly this shape across chat.js and face_speech_runtime.js —
  #
  #   -  text.slice(0, cut) + ' — *cough* — ' + text.slice(cut + 1)
  #   +  text.slice(0, cut) + ` — *cough* — ${text.slice}`(cut + 1)
  #
  # — and they sat in the tree for a day. Only chat.js was caught, indirectly,
  # by the manifest-drift test above, and only because the digested copy still
  # held the pre-sweep version; face_speech_runtime.js was never noticed at all,
  # because face.runtime.js had not been rebuilt since. Precompiling would have
  # "resolved" that drift by copying the broken source over the good asset.
  def test_public_js_has_no_template_literal_called_as_a_function
    public_dir = File.expand_path("../web/public", __dir__)
    sources = Dir[File.join(public_dir, "*.js")] + Dir[File.join(public_dir, "face.part*.txt")]
    offenders = sources.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, i|
        next unless line.match?(/`[^`]*\$\{[^}]*\}[^`]*`\s*\(/)

        "#{File.basename(path)}:#{i + 1} #{line.strip[0, 100]}"
      end
    end

    assert_empty offenders,
                 "template literal called as a function (TypeError at runtime, parses fine):\n" +
                 offenders.join("\n")
  end

  # Reads web/config/face_assets.yml, which the view now renders from, rather
  # than scraping a javascript_include_tag(*%w[...]) literal out of the ERB.
  def boot_manifest_sources(index)
    manifest = YAML.safe_load_file(File.expand_path("../web/config/face_assets.yml", __dir__))
    manifest_js = Array(manifest["shell_manifest"]).map { |name| "#{name}.js" }
    face_parts = index.scan(/face\.part\d+\.txt/).uniq.sort

    (manifest_js + Array(manifest["shell_blocking"]) + face_parts).uniq
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
      m = Master::Ground::Memory.new(root: dir)
      m.remember(:user_name, "Osman")
      assert_equal "Osman", m.recall(:user_name)
    end
  end

  def test_memory_context_summary_nil_when_empty
    Dir.mktmpdir do |dir|
      m = Master::Ground::Memory.new(root: dir)
      %w[brain/memory brain/tools brain/identity].each { |key| m.forget(key) }
      assert_nil m.context_summary
    end
  end

  def test_memory_context_summary_lists_keys
    Dir.mktmpdir do |dir|
      m = Master::Ground::Memory.new(root: dir)
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

  # face.js fetches public/face.runtime.js and imports it as one blob; it never
  # fetches the sources. So the built file is what runs, and it is generated by
  # assets:build_face_runtime, which assets:precompile enhances — meaning a hand
  # edit to the built file survives until the next deploy and then vanishes,
  # while an edit to a source alone does nothing until one runs.
  #
  # Nothing asserted the two agreed. This does, by rebuilding exactly as the
  # rake task does. If it fails, run `rails assets:build_face_runtime` in
  # MASTER/web and commit the result.
  #
  # Two of the six sources are .js files, not face.part*.txt — the speech
  # runtime and playback, which is where TTS and the browser-voice default live.
  # Reading the docs' "generated from face.part*.txt" as the whole list sends
  # you looking for that code in a part file that does not contain it.
  FACE_RUNTIME_SOURCES = %w[
    face.part1.txt face.part2.txt face.part3.txt
    face_speech_runtime.js face_speech_playback.js
    face.part5.txt
  ].freeze

  FACE_RUNTIME_BANNER =
    "// Generated by rails assets:build_face_runtime — do not edit by hand.\n" \
    "// Import map + MASTER_ASSET_PATHS resolve tail module imports at runtime.\n"

  def test_face_runtime_matches_its_sources
    dir = File.expand_path("../web/public", __dir__)
    missing = FACE_RUNTIME_SOURCES.reject { |name| File.file?(File.join(dir, name)) }
    assert_empty missing, "face runtime sources missing: #{missing.join(', ')}"

    body = FACE_RUNTIME_SOURCES.map { |name| File.read(File.join(dir, name)) }.join("\n")
    rebuilt = "#{FACE_RUNTIME_BANNER}#{body}\n"
    built = File.read(File.join(dir, "face.runtime.js"))

    assert_equal rebuilt.bytesize, built.bytesize,
                 "public/face.runtime.js has drifted from its sources — " \
                 "run `rails assets:build_face_runtime` in MASTER/web"
    assert_equal rebuilt, built,
                 "public/face.runtime.js differs from its sources at equal length"
  end
end
