# frozen_string_literal: true

class TtsController < ApplicationController
  def show
    text = params[:text].to_s.strip
    return head(:bad_request) if text.empty?

    voice_key, synth_style, rate, pitch = tts_voice_and_style(text)
    publish_tts_style(voice_key, synth_style)
    job = TtsJob.enqueue(text: text, voice: voice_key, style: synth_style, rate: rate, pitch: pitch, bus: container[:bus])
    etag = %("#{job.job_id}")
    response.headers["X-TTS-Voice"] = voice_key.to_s
    response.headers["X-TTS-Job"] = job.job_id
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "public, max-age=3600"
    return head(:not_modified) if request.headers["If-None-Match"].to_s.split(",").map(&:strip).include?(etag)

    tts_job_response(job)
  rescue StandardError => e
    web_logger.warn("tts failed: #{e.class}: #{e.message}")
    render(json: { error: e.message, status: "failed" }, status: :service_unavailable)
  end

  def status
    job = TtsJob.find(params[:job].to_s)
    return head(:not_found) unless job

    tts_job_response(job)
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

  def resolve_tts_voice(raw, fallback_voice = nil)
    candidate = raw.to_s.strip
    candidate = fallback_voice.to_s if candidate.empty? && fallback_voice
    Master::Voice::Speech.resolve_voice(candidate.empty? ? Master::Voice::Speech::DEFAULT_VOICE : candidate)
  end

  def resolve_tts_style(raw_style, text)
    style = raw_style.to_s.strip.to_sym
    return style if Master::Voice::Speech::STYLES.key?(style)

    Master::Voice::Speech.infer_style(text, fallback: Master::Voice::Speech.default_style)
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
