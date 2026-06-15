# frozen_string_literal: true

require "base64"
require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "securerandom"

class ChatController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :command

  COUNCIL_PERSONA_VOICE = {
    "Architect" => :davis,
    "Skeptic" => :wayne,
    "Pragmatist" => :davis,
    "Security" => :wayne,
    "User" => :davis,
    "Mentor" => :ezinne
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
    cmd = (params[:command] || JSON.parse(request.body.read)["command"]).to_s.strip
    if cmd.start_with?("/unlock ")
      pw = cmd.sub(/^\/unlock\s+/, "").strip
      token = ENV["MASTER_WEB_TOKEN"].to_s
      if token.empty? || pw != token
        render(json: { output: "unlock denied" }, status: 401) and return
      end
      cookies[:master_unlocked] = { value: "1", expires: 1.year.from_now, secure: true, httponly: true, same_site: :strict }
      render(json: { output: "unlocked — full tool access enabled." }) and return
    end
    return head(:forbidden) if visitor? && cmd.start_with?("/")

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
    container[:bus]&.publish("tts:error", error: e.message)
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
    container[:bus]&.publish("photo:error", error: e.message)
    render json: { error: "photo upload failed" }, status: 500
  end

  def message
    mp = message_params
    input = mp[:message].to_s.strip
    return head(:bad_request) if input.empty?
    return head(:forbidden) if visitor? && input.start_with?("/")

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    visitor = request.env["master.tier"] != "authenticated"
    Fiber[:master_visitor] = visitor
    Fiber[:master_elevated] = cookies[:master_unlocked].to_s == "1" || cookies[:master_author].to_s.present?

    sse = response.stream
    begin
      ChatService.new(container:, sse:, message_params: mp, visitor:).stream_turn!
    rescue StandardError => e
      sse.write("data: ERROR: #{e.message}\n\n")
      sse.write("data: [DONE]\n\n")
    ensure
      Fiber[:master_visitor] = nil
      Fiber[:master_elevated] = nil
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
    container[:bus]&.publish("photo:cleanup_skip", error: e.message)
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
    container[:bus]&.publish("photo:postpro", status: status.exitstatus, file: File.basename(input_path))
    status.success?
  rescue StandardError => e
    container[:bus]&.publish("photo:postpro_error", error: e.message)
    false
  end
end