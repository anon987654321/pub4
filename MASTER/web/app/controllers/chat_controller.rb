# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "securerandom"

class ChatController < ApplicationController
  # CSRF guarded by SameSite=Strict session cookie set in AuthTier.
  skip_before_action :verify_authenticity_token, only: :command

  COUNCIL_PERSONA_VOICE = {
    "Architect" => :ryan,
    "Skeptic" => :steffan,
    "Pragmatist" => :finn,
    "Security" => :osman,
    "User" => :ryan,
    "Mentor" => :yasmin
  }.freeze

  PHOTO_UPLOAD_DIR = Rails.root.join("tmp", "chat_uploads")
  PHOTO_MAX_BYTES = Integer(ENV.fetch("MASTER_PHOTO_MAX_BYTES", 12 * 1024 * 1024))
  PHOTO_MIME_EXT = {
    "image/jpeg" => ".jpg",
    "image/png" => ".png",
    "image/webp" => ".webp",
    "image/heic" => ".heic",
    "image/heif" => ".heif"
  }.freeze
  DEFAULT_POSTPRO_PRESET = ENV.fetch("MASTER_POSTPRO_PRESET", "portrait")

  def index
    @model = container[:agent].model.to_s.split("/").last
    @tier  = request.env["master.tier"].to_s
    render layout: false
  end

  def dmesg
    out, = Open3.capture2e("dmesg")
    lines = out.lines.first(20).map(&:chomp)
    render json: { lines: lines }
  end

  def metrics
    c = container
    repo_root = Rails.root.join("..").to_s
    out, = Open3.capture2e("git", "-C", repo_root, "status", "--porcelain")
    dirty = out.lines.count
    open_models = c[:breaker].respond_to?(:open_models) ? c[:breaker].open_models : []
    render json: {
      model:            c[:agent].model.to_s.split("/").last,
      tokens:           c[:session].respond_to?(:token_est) ? c[:session].token_est : 0,
      cost:             "$%.4f" % (c[:session].respond_to?(:cost) ? c[:session].cost : 0.0),
      uptime:           ((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i - start_ms),
      repo_dirty_count: dirty,
      open_breakers:    open_models,
      tier:             request.env["master.tier"].to_s
    }
  end

  def history
    messages = container[:session].messages.last(200).map { |m| { role: m[:role], content: m[:content].to_s[0, 2000] } }
    render json: messages
  end

  def command
    cmd = params[:command] || JSON.parse(request.body.read)["command"]
    return head(:forbidden) if visitor? && cmd.to_s.strip.start_with?("/")

    result = container[:gateway].receive(channel: :cli, message: cmd)
    output = result.ok? ? (result.value[:rendered] || result.value.to_s) : result.message
    render json: { output: output }
  rescue StandardError => e
    render json: { output: "Error: #{e.message}" }, status: 500
  end

  def tts
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?

    voice_key = params[:voice].to_s.strip.to_sym
    voice_key = Master::Voice::Speech::DEFAULT_VOICE unless Master::Voice::Speech::VOICES.key?(voice_key)

    style = params[:style].to_s.strip.to_sym
    if Master::Voice::Speech::STYLES.key?(style) && ![:neutral, :normal].include?(style)
      voice_key = params[:voice].to_s.strip.to_sym
      voice_key = Master::Voice::Speech::DEFAULT_VOICE unless Master::Voice::Speech::VOICES.key?(voice_key)
      cfg = Master::Voice::Speech.style_config_for(voice_key, style)
      expr = Master::Voice::Expression.for_tts_style(style)
      container[:bus]&.publish("tts:style:active", style: style.to_s, rate: cfg[:rate], pitch: cfg[:pitch], expression: expr)

      # Pre-speech anticipation (pending idea): brief arousal + eye widening signal before audio starts
      anticipate = expr.dup
      anticipate[:arousal] = (anticipate[:arousal] || 0.7) + 0.25
      anticipate[:attention] = (anticipate[:attention] || 0.6) + 0.3
      container[:bus]&.publish("tts:anticipate", style: style.to_s, expression: anticipate)
    end

    synth_style = Master::Voice::Speech::STYLES.key?(style) ? style : :auto
    tts_fingerprint = Digest::SHA256.hexdigest("#{voice_key}|#{synth_style}|#{text}")
    etag = %("#{tts_fingerprint}")
    response.headers["X-TTS-Voice"] = voice_key.to_s
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=3600"
    return head(:not_modified) if request.headers["If-None-Match"].to_s.split(",").map(&:strip).include?(etag)

    cache_key = tts_fingerprint[0, 32]
    cache_dir = Rails.root.join("tmp", "tts_cache")
    cache_path = cache_dir.join("#{cache_key}.mp3")

    bytes = if File.file?(cache_path)
      File.binread(cache_path)
    else
      b = Master::Voice::Speech.synthesize_bytes(text, voice: voice_key, style: synth_style)
      if b && !b.empty?
        FileUtils.mkdir_p(cache_dir)
        File.binwrite(cache_path, b)
      end
      b
    end
    return head(:service_unavailable) if bytes.nil? || bytes.empty?

    send_data bytes, type: Master::Voice::Speech.mime_type_for(".mp3"), disposition: "inline"
  rescue StandardError => e
    Rails.logger.warn("tts failed: #{e.class}: #{e.message}")
    head(:internal_server_error)
  end

  def enhance
    msg = params[:message].to_s.strip
    return render(json: { changed: false }) if msg.empty?

    result = Master::Now::Stages::Enhance.run(msg, agent: container[:agent], event_bus: container[:bus])
    render json: result
  rescue StandardError => e
    render json: { changed: false, error: e.message }
  end

  def photo
    upload = params[:photo]
    return render(json: { error: "missing photo" }, status: :bad_request) unless upload.respond_to?(:read)

    mime = upload.content_type.to_s.downcase
    ext = PHOTO_MIME_EXT[mime]
    return render(json: { error: "unsupported image type" }, status: :unsupported_media_type) unless ext

    size = upload.respond_to?(:size) ? upload.size.to_i : 0
    return render(json: { error: "photo too large" }, status: :payload_too_large) if size > PHOTO_MAX_BYTES

    FileUtils.mkdir_p(PHOTO_UPLOAD_DIR)
    cleanup_old_photos!

    token = SecureRandom.hex(12)
    safe_name = sanitize_filename(upload.original_filename.to_s, fallback_ext: ext)
    original_path = PHOTO_UPLOAD_DIR.join("#{token}_orig#{ext}")
    processed_path = PHOTO_UPLOAD_DIR.join("#{token}_#{DEFAULT_POSTPRO_PRESET}#{ext}")

    File.binwrite(original_path, upload.read)
    processed = postpro_photo(original_path.to_s, processed_path.to_s)
    final_path = processed && File.file?(processed_path) ? processed_path : original_path

    info = {
      "token" => token,
      "path" => final_path.to_s,
      "original_path" => original_path.to_s,
      "name" => safe_name,
      "mime" => mime,
      "processed" => final_path == processed_path,
      "preset" => DEFAULT_POSTPRO_PRESET,
      "created_at" => Time.now.utc.iso8601
    }
    File.write(PHOTO_UPLOAD_DIR.join("#{token}.json"), JSON.pretty_generate(info))
    render json: { token: token, name: safe_name, processed: info["processed"], preset: DEFAULT_POSTPRO_PRESET }
  rescue StandardError => e
    Rails.logger.warn("photo upload failed: #{e.class}: #{e.message}")
    render json: { error: "photo upload failed" }, status: 500
  end

  def message
    mp = message_params
    input = mp[:message].to_s.strip
    return head(:bad_request) if input.empty?
    return head(:forbidden) if visitor? && input.start_with?("/")

    container[:bus].publish("user:interrupt", reason: "new_turn", source: "chat")
    container[:bus]&.publish("input:long", length: input.length) if input.length > 180

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    visitor = request.env["master.tier"] != "authenticated"
    Fiber[:master_visitor] = visitor

    sse = response.stream
    begin
      streamed  = false
      tool_sub  = container[:bus].subscribe("tool:before") do |ev|
        begin
          payload = { tool: ev[:tool].to_s, path: ev[:path].to_s }.to_json
          sse.write("event: tool\ndata: #{payload}\n\n")
        rescue StandardError => _e
          nil
        end
      end
      # Bridge bus state → named SSE events so the face UI can react gesturally.
      mood_sub      = container[:bus].subscribe("agent:mood")        { |ev| sse.write("event: mood\ndata: #{ev[:mood] || ev[:value]}\n\n") rescue nil }
      model_sub     = container[:bus].subscribe("llm:request")       { |ev| sse.write("event: model\ndata: #{ev[:model]}\n\n") rescue nil }
      # dmesg stream — all bus activity as OpenBSD dmesg(8)-style dim lines.
      dmesg_sub = container[:bus].subscribe("**") do |ev|
        line = dmesg_format(ev[:event].to_s, ev)
        sse.write("event: dmesg\ndata: #{line.to_json}\n\n") rescue nil
      end
      thought_sub = container[:bus].subscribe("**") do |ev|
        line = thought_format(ev[:event].to_s, ev)
        sse.write("event: thought\ndata: #{line.to_json}\n\n") rescue nil if line
      end
      verdict_sub   = container[:bus].subscribe("tribunal:rendered") do |ev|
        v = ev[:vetoes].to_i.positive? ? "veto" : (ev[:judge] ? "pass" : "unclear")
        sse.write("event: verdict\ndata: #{v}\n\n") rescue nil
      end
      escalate_sub  = container[:bus].subscribe("llm:escalation")    { |_| sse.write("event: confidence\ndata: 0.4\n\n") rescue nil }
      enhance_sub   = container[:bus].subscribe("enhance:rewrite") do |ev|
        sse.write("event: enhance\ndata: #{ev[:enhanced].to_s.gsub("\n", "\\n").to_json}\n\n") rescue nil
      end
      council_sub = container[:bus].subscribe(:council_feedback) do |ev|
        persona = ev[:persona].to_s
        voice = COUNCIL_PERSONA_VOICE[persona] || Master::Voice::Speech::DEFAULT_VOICE
        raw = ev[:feedback].to_s.strip
        sentence = raw.split(/(?<=[.!?])\s+/).first(2).join(" ").strip[0, 200]
        next if sentence.empty?
        payload = { voice: voice.to_s, text: sentence, persona: persona }.to_json
        sse.write("event: council:speech\ndata: #{payload}\n\n") rescue nil
      end
      # Publish incoming canvas state into bus so prompt-builder can include it.
      if (st = mp[:state]).present?
        mood, mode, idle_s, palette = st.to_s.split("|")
        container[:bus].publish(:canvas_state, mood:, mode:, idle_s: idle_s.to_i, palette: palette.to_i) rescue nil
      end

      on_chunk = ->(token) {
        t = token.to_s
        return if t.empty?
        streamed = true
        sse.write("data: #{t.gsub("\\", "\\\\").gsub("\n", "\\n")}\n\n")
      }

      ctx = { user_message: input, on_chunk: on_chunk }
      ctx[:pre_enhanced] = true if mp[:pre_enhanced].present?
      ctx[:voice] = true if mp[:voice].present?
      if (img = mp[:image]).present?
        ctx[:image] = { data: img[:data].to_s, mime: img[:mime].to_s, name: img[:name].to_s }
      elsif (token = mp[:image_token]).present?
        payload = uploaded_image_payload(token)
        ctx[:image] = payload if payload
      end

      mutated_flag    = false
      mutated_paths   = []
      mutate_sub = container[:bus].subscribe("tool:after") do |ev|
        next unless %w[Write Edit Create FilePatch].include?(ev[:tool].to_s)
        mutated_flag = true
        path = ev[:path].to_s
        mutated_paths << path unless path.empty?
      end

      result = container[:pipeline].call(Master::Result.ok(**ctx))

      unless streamed
        text = case result
               when Master::Result::Ok
                 val = result.value
                 rendered = val.respond_to?(:[]) ? val[:rendered].to_s : ""
                 rendered.empty? ? val.to_s : rendered
               when Master::Result::Err
                 result.category == :no_api_key ? result.message : "ERROR: #{result.message}"
               end
        unless text.to_s.strip.empty?
          encoded = text.to_s.gsub("\\", "\\\\").gsub("\n", "\\n")
          sse.write("data: #{encoded}\n\n")
        end
      end

      sse.write("data: [DONE]\n\n")

      if mutated_flag
        container[:bus].publish("auto:auto_start", reason: "post_chat_mutation")
        if mutated_paths.any?
          Thread.new do
            Thread.current.report_on_exception = false
            repo_root = Rails.root.join("..", "..").to_s
            msg = "auto: chat-turn mutation (#{mutated_paths.size} file(s))"
            paths_to_add = mutated_paths.select { |p| File.exist?(p) }
            next if paths_to_add.empty?
            _, status = Open3.capture2e("git", "-C", repo_root, "add", "--", *paths_to_add)
            if status.success?
              _, st = Open3.capture2e("git", "-C", repo_root, "commit", "-m", msg)
              container[:bus].publish("autocommit:done", ok: st.success?)
            end
          rescue StandardError => err
            container[:bus].publish("autocommit:error", error: err.message)
          end
        end
      end
    rescue StandardError => e
      sse.write("data: ERROR: #{e.message}\n\n")
      sse.write("data: [DONE]\n\n")
    ensure
      Fiber[:master_visitor] = nil
      begin
        tool_sub.call if defined?(tool_sub) && tool_sub
        mutate_sub.call if defined?(mutate_sub) && mutate_sub
        mood_sub.call if defined?(mood_sub) && mood_sub
        model_sub.call if defined?(model_sub) && model_sub
        verdict_sub.call if defined?(verdict_sub) && verdict_sub
        escalate_sub.call if defined?(escalate_sub) && escalate_sub
        enhance_sub.call  if defined?(enhance_sub)  && enhance_sub
        council_sub.call  if defined?(council_sub)  && council_sub
        dmesg_sub.call    if defined?(dmesg_sub)    && dmesg_sub
        thought_sub.call  if defined?(thought_sub)  && thought_sub
      rescue StandardError => _e
        nil
      end
      sse.close
    end
  end

  private

  def message_params
    params.permit(:message, :state, :pre_enhanced, :voice, :image_token, image: %i[data mime name])
  end

  def cleanup_old_photos!
    cutoff = Time.now - 86_400
    Dir.glob(PHOTO_UPLOAD_DIR.join("*")).each do |path|
      File.delete(path) if File.file?(path) && File.mtime(path) < cutoff
    end
  rescue StandardError => e
    Rails.logger.debug("photo cleanup skipped: #{e.message}")
  end

  def sanitize_filename(name, fallback_ext: ".jpg")
    ext = File.extname(name.to_s).downcase
    ext = fallback_ext if ext.empty?
    stem = File.basename(name.to_s, ext).gsub(/[^A-Za-z0-9._-]+/, "_").sub(/\A[._-]+/, "")
    stem = "photo" if stem.empty?
    "#{stem}#{ext}"
  end

  def postpro_photo(input_path, output_path)
    script = Rails.root.join("..", "tools", "postpro.rb").to_s
    return false unless File.file?(script)

    out, status = Open3.capture2e(
      RbConfig.ruby,
      script,
      "--input", input_path,
      "--output", output_path,
      "--preset", DEFAULT_POSTPRO_PRESET,
      chdir: Rails.root.join("..", "..").to_s
    )
    Rails.logger.info("postpro photo=#{File.basename(input_path)} status=#{status.exitstatus} out=#{out.lines.last}")
    status.success?
  rescue StandardError => e
    Rails.logger.warn("postpro failed: #{e.class}: #{e.message}")
    false
  end

  def uploaded_image_payload(token)
    return nil unless token.to_s.match?(/\A[0-9a-f]{24}\z/)

    meta_path = PHOTO_UPLOAD_DIR.join("#{token}.json")
    return nil unless File.file?(meta_path)

    meta = JSON.parse(File.read(meta_path))
    disk_path = meta["path"].to_s
    return nil unless disk_path.start_with?(PHOTO_UPLOAD_DIR.to_s)
    return nil unless File.file?(disk_path)

    {
      data: Base64.strict_encode64(File.binread(disk_path)),
      mime: meta["mime"].to_s.empty? ? "image/jpeg" : meta["mime"].to_s,
      name: meta["name"].to_s.empty? ? File.basename(disk_path) : meta["name"].to_s,
      path: disk_path  # prefer for RubyLLM::Attachment (loads from disk, vision models)
    }
  rescue StandardError => e
    Rails.logger.warn("uploaded_image_payload failed: #{e.class}: #{e.message}")
    nil
  end

  # Format any bus event as an OpenBSD dmesg(8)-style line.
  # Pattern: <subsystem><unit> at <bus>: <description>
def thought_format(event, payload)
  case event
  when "enhance:rewrite"
    "refining your prompt for clarity"
  when "llm:request"
    model = payload[:model].to_s.split("/").last
    model.empty? ? "thinking" : "thinking with #{model}"
  when "llm:escalation"
    "escalating to a deeper model (depth #{payload[:depth]})"
  when "tool:before"
    tool = payload[:tool].to_s.split("::").last.to_s.downcase
    path = payload[:path].to_s
    path.empty? ? "using #{tool}" : "using #{tool} on #{File.basename(path)}"
  when "council_feedback", :council_feedback
    persona = payload[:persona].to_s
    persona.empty? ? "council deliberating" : "#{persona} weighs in"
  when "tribunal:rendered"
    v = payload[:vetoes].to_i.positive? ? "vetoed" : "approved"
    "tribunal #{v}"
  when "pipeline:stage"
    stage = payload[:stage].to_s
    %w[enhance infer route guard execute council deliberate prune memo render].include?(stage) ? "entering #{stage}" : nil
  end
end

  def dmesg_format(event, payload)
    sub, rest = event.split(":", 2)
    desc = case event
           when "tool:before"
             tool = payload[:tool].to_s.downcase.split("::").last
             path = payload[:path].to_s
             path.empty? ? tool : "#{tool} #{path}"
           when "llm:request"
             model = payload[:model].to_s.split("/").last
             tokens = payload[:tokens]
             tokens ? "→ #{model} (#{tokens} tokens)" : "→ #{model}"
           when "llm:escalation"    then "escalation depth #{payload[:depth]}"
           when "enhance:rewrite"
             o = payload[:original].to_s.length
             e = payload[:enhanced].to_s.length
             "rewrite #{o}→#{e} chars"
           when "pipeline:rollback" then "rollback #{payload[:category]} #{payload[:tag].to_s.split(":").last}"
           when "pipeline:stage"    then "stage #{payload[:stage]} #{payload[:ms]}ms"
           when "fix_loop:pass_start" then "pass #{payload[:pass]}"
           when "fix_loop:clean"      then "clean #{payload[:consecutive_clean]}/2"
           when "fix_loop:plateau"    then "plateau #{payload[:violations]} violations"
           when "fix_loop:ast_fixed"  then "ast #{payload[:transforms]&.join(",")}"
           when "tribunal:rendered"
             v = payload[:vetoes].to_i.positive? ? "veto" : "pass"
             "#{v} #{payload[:judge]}"
           when "backup:ok"         then "synced #{payload[:bytes]}B"
           when "backup:error"      then "error #{payload[:error]}"
           when "scan:complete"     then "#{payload[:count]} violations"
           when "autoloop:cycle"    then "autoloop #{payload[:pass]}/#{payload[:max]}"
           when "pressure:updated"  then return nil  # too noisy — skip
           when /\Apipeline:/       then return nil  # internal, skip
           when /\Acanvas_/         then return nil
           else
             rest&.tr("_", " ") || sub
           end
    return nil if desc.nil?
    "#{sub}0 at master0: #{desc}"
  end
end
