# frozen_string_literal: true

require "base64"
require "json"

class TtsController < ApplicationController
  def show
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?

    voice_locked = ActiveModel::Type::Boolean.new.cast(params[:voice_locked]) == true
    style_locked = ActiveModel::Type::Boolean.new.cast(params[:style_locked]) == true
    voice_key, synth_style, rate, pitch = tts_voice_and_style(text)
    pre = Master::Voice::Expression.for_pre_speech(style: synth_style, text: text)
    container[:bus]&.publish("tts:anticipate", style: synth_style.to_s, expression: pre)
    publish_tts_style(voice_key, synth_style, text: text)
    job = TtsJob.enqueue(
      text: text,
      voice: voice_key,
      style: synth_style,
      rate: rate,
      pitch: pitch,
      voice_locked: voice_locked,
      style_locked: style_locked,
      bus: container[:bus]
    )
    stream = Master::Voice::Expression.viseme_stream(text, style: synth_style, rate: rate)
    etag = %("#{job.job_id}")
    response.headers["X-TTS-Voice"] = voice_key.to_s
    response.headers["X-TTS-Style"] = synth_style.to_s
    response.headers["X-TTS-Visemes"] = viseme_header(stream[:viseme_plan] || stream[:visemes])
    response.headers["X-TTS-Job"] = job.job_id
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=3600"
    return head(:not_modified) if request.headers["If-None-Match"].to_s.split(",").map(&:strip).include?(etag)

    tts_job_response(job)
  rescue StandardError => e
    web_logger.warn("tts failed: #{e.class}: #{e.message}")
    render(json: { error: e.message, status: "failed" }, status: :service_unavailable)
  end

  def phrases
    raw = Master::Ground::RuntimeCatalog.load("tts_phrases")
    list = Array(raw["phrases"]).map do |row|
      {
        text: row["text"].to_s,
        voice: row["voice"].to_s,
        style: row["style"].to_s,
      }
    end
    render json: { phrases: list }
  end

  def status
    job = TtsJob.find(params[:job].to_s)
    return head(:not_found) unless job

    TtsJob.materialize!(job) if job.pending?
    tts_job_response(job)
  end

  def stream
    job = TtsJob.find(params[:job].to_s)
    return head(:not_found) unless job

    TtsJob.materialize!(job) if job.pending?

    if job.ready?
      bytes = job.bytes
      return head(:not_found) if bytes.nil? || bytes.empty?

      return send_data bytes, type: Master::Voice::Speech.mime_type_for(".mp3"), disposition: "inline"
    end

    partial = job.partial_bytes
    return head(:accepted) if partial.nil? || partial.empty?

    attach_pending_viseme_headers(job)
    response.headers["X-TTS-Bytes"] = partial.bytesize.to_s
    response.headers["X-TTS-Partial"] = "1"
    send_data partial, type: Master::Voice::Speech.mime_type_for(".mp3"), disposition: "inline", status: :partial_content
  end

  def destroy
    job_id = params[:job].to_s
    return head(:bad_request) if job_id.empty?

    cancelled = TtsJob.cancel(job_id)
    return head(:not_found) unless cancelled

    container[:bus]&.publish("tts:job_cancelled", job_id: job_id)
    head(:no_content)
  end

  private

  def web_logger
    @web_logger ||= WebEventLogger.new(container[:bus])
  end

  def tts_voice_and_style(text)
    personality = container[:personality]
    voice_key = resolve_tts_voice(params[:voice], personality&.voice)
    synth_style = resolve_tts_style(params[:style], text)
    rate = params[:rate].presence || personality&.tts_rate
    pitch = params[:pitch].presence || personality&.tts_pitch
    [voice_key, synth_style, rate, pitch]
  end

  def resolve_tts_voice(_raw, _fallback_voice = nil)
    Master::Voice::Speech.resolve_voice(Master::Voice::Policy.single_voice_key)
  end

  def resolve_tts_style(raw_style, text)
    style = raw_style.to_s.strip.to_sym
    return style if Master::Voice::Speech::STYLES.key?(style)

    Master::Voice::Speech.infer_style(text, fallback: Master::Voice::Speech.default_style)
  end

  def viseme_header(visemes)
    json = JSON.generate(visemes)
    json.length <= 240 ? json : Base64.strict_encode64(json)
  end

  def tts_job_response(job)
    if job.failed?
      return render(json: { job: job.job_id, status: "failed", error: job.error }, status: :service_unavailable)
    end
    if job.pending?
      attach_pending_viseme_headers(job)
      avail = job.bytes_available
      response.headers["X-TTS-Bytes"] = avail.to_s if avail.positive?
      return render(json: { job: job.job_id, status: "pending", bytes: avail }, status: :accepted)
    end

    bytes = job.bytes
    return render(json: { job: job.job_id, status: "failed", error: "empty audio" }, status: :service_unavailable) if bytes.nil? || bytes.empty?

    meta = job.meta
    if meta
      response.headers["X-TTS-Meta"] = viseme_header(meta)
      visemes = meta["viseme_plan"] || meta["viseme_hints"]
      response.headers["X-TTS-Visemes"] = viseme_header(visemes) if visemes
    end
    send_data bytes, type: Master::Voice::Speech.mime_type_for(".mp3"), disposition: "inline"
  end

  def attach_pending_viseme_headers(job)
    token_path = Rails.root.join("tmp", "tts_cache", "#{job.job_id}.job")
    return unless File.file?(token_path)

    data = JSON.parse(File.read(token_path))
    stream = Master::Voice::Expression.viseme_stream(
      data["text"],
      style: data["style"],
      rate: data["rate"]
    )
    response.headers["X-TTS-Visemes"] = viseme_header(stream[:viseme_plan] || stream[:visemes])
  rescue StandardError
    nil
  end

  def publish_tts_style(voice_key, synth_style, text: nil)
    return if [:neutral, :normal].include?(synth_style)
    return unless Master::Voice::Speech::STYLES.key?(synth_style)

    cfg = Master::Voice::Speech.style_config_for(voice_key, synth_style)
    expr = Master::Voice::Expression.for_tts_style(synth_style)
    container[:bus]&.publish("tts:style:active", style: synth_style.to_s, rate: cfg[:rate], pitch: cfg[:pitch], expression: expr)
    stream = text ? Master::Voice::Expression.viseme_stream(text, style: synth_style) : {}
    blendshapes = Master::Voice::Expression.blendshapes_for(synth_style)
    container[:bus]&.publish(
      "tts:viseme:plan",
      style: synth_style.to_s,
      visemes: stream[:visemes] || [],
      viseme_plan: stream[:viseme_plan] || [],
      duration_ms: stream[:duration_ms],
      blendshapes: blendshapes
    )
  end
end
