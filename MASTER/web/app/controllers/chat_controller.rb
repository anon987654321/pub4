# frozen_string_literal: true

require "digest"
require "json"
require "open3"

class ChatController < ApplicationController
  # CSRF guarded by SameSite=Strict session cookie set in AuthTier.
  skip_before_action :verify_authenticity_token, only: :command

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

    voice_key, synth_style = tts_voice_and_style
    publish_tts_style(voice_key, synth_style)
    job = TtsJob.enqueue(text: text, voice: voice_key, style: synth_style, bus: container[:bus])
    etag = %("#{job.job_id}")
    response.headers["X-TTS-Voice"] = voice_key.to_s
    response.headers["X-TTS-Job"] = job.job_id
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=3600"
    return head(:not_modified) if request.headers["If-None-Match"].to_s.split(",").map(&:strip).include?(etag)
    return tts_job_response(job)
  rescue StandardError => e
    web_logger.warn("tts failed: #{e.class}: #{e.message}")
    render(json: { error: e.message, status: "failed" }, status: :service_unavailable)
  end

  def tts_status
    job = TtsJob.find(params[:job].to_s)
    return head(:not_found) unless job

    tts_job_response(job)
  end


  def research
    n = params[:n].to_i.clamp(1, 30)
    n = 10 if n.zero?
    require "net/http"
    require "uri"
    cats = %w[cs.AI cs.LG cs.CL cs.NE q-bio physics.gen-ph astro-ph]
    q = cats.map { |c| "cat:#{c}" }.join("+OR+")
    uri = URI("https://export.arxiv.org/api/query?search_query=#{q}&sortBy=submittedDate&sortOrder=descending&max_results=#{n}")
    body = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 4, read_timeout: 6) { |h| h.get(uri.request_uri).body }
    items = body.to_s.scan(/<entry>(.*?)<\/entry>/m).map do |entry|
      entry = entry.first
      t = entry[/<title>(.*?)<\/title>/m, 1].to_s.gsub(/\s+/, " ").strip
      s = entry[/<summary>(.*?)<\/summary>/m, 1].to_s.gsub(/\s+/, " ").strip.split(/(?<=[.!?])\s+/).first(2).to_a.join(" ")
      next if t.empty?
      "#{t}. #{s}".slice(0, 480)
    end.compact
    render json: { items: items }
  rescue StandardError => e
    web_logger.warn("research failed: #{e.class}: #{e.message}")
    render json: { items: [] }
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
    status, payload = ImagePresenter.new(logger: web_logger).store(params[:photo])
    render json: payload, status: status
  end

  def message
    mp = message_params
    input = mp[:message].to_s.strip
    return head(:bad_request) if input.empty?
    return head(:forbidden) if visitor? && input.start_with?("/")

    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    ChatService.new(
      container: container,
      params: mp,
      stream: response.stream,
      logger: web_logger,
      tier: request.env["master.tier"].to_s,
      unlocked: cookies[:master_unlocked].to_s == "1",
      author: cookies[:master_author].to_s.present?
    ).call
  end

  private

  def message_params
    params.permit(:message, :state, :pre_enhanced, :voice, :image_token, image: %i[data mime name])
  end

  def web_logger
    @web_logger ||= WebEventLogger.new(container[:bus])
  end

  def tts_voice_and_style
    voice_key = params[:voice].to_s.strip.to_sym
    voice_key = Master::Voice::Speech::DEFAULT_VOICE unless Master::Voice::Speech::VOICES.key?(voice_key)
    style = params[:style].to_s.strip.to_sym
    synth_style = Master::Voice::Speech::STYLES.key?(style) ? style : :auto
    [voice_key, synth_style]
  end

  def tts_job_response(job)
    if job.failed?
      return render(json: { job: job.job_id, status: "failed", error: job.error }, status: :service_unavailable)
    end
    return render(json: { job: job.job_id, status: "pending" }, status: :accepted) if job.pending?

    bytes = job.bytes
    return render(json: { job: job.job_id, status: "failed", error: "empty audio" }, status: :service_unavailable) if bytes.nil? || bytes.empty?

    send_data bytes, type: Master::Voice::Speech.mime_type_for(".mp3"), disposition: "inline"
  end

  def publish_tts_style(voice_key, synth_style)
    return if [:neutral, :normal].include?(synth_style)
    return unless Master::Voice::Speech::STYLES.key?(synth_style)

    cfg = Master::Voice::Speech.style_config_for(voice_key, synth_style)
    expr = Master::Voice::Expression.for_tts_style(synth_style)
    container[:bus]&.publish("tts:style:active", style: synth_style.to_s, rate: cfg[:rate], pitch: cfg[:pitch], expression: expr)
    anticipate = expr.dup
    anticipate[:arousal] = (anticipate[:arousal] || 0.7) + 0.25
    anticipate[:attention] = (anticipate[:attention] || 0.6) + 0.3
    container[:bus]&.publish("tts:anticipate", style: synth_style.to_s, expression: anticipate)
  end

end
