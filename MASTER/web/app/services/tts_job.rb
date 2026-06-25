# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

class TtsJob
  CACHE_DIR = Rails.root.join("tmp", "tts_cache")

  def self.enqueue(text:, voice:, style:, rate: nil, pitch: nil, voice_locked: false, style_locked: false, bus: nil)
    job = new(
      text: text,
      voice: voice,
      style: style,
      rate: rate,
      pitch: pitch,
      voice_locked: voice_locked,
      style_locked: style_locked,
      bus: bus
    )
    return job if job.ready?
    return job if job.failed?

    Thread.new do
      Thread.current.report_on_exception = false
      job.perform
    end
    job
  end

  def self.find(job_id)
    return nil unless job_id.to_s.match?(/\A[0-9a-f]{32}\z/)

    token_path = CACHE_DIR.join("#{job_id}.job")
    return nil unless File.file?(token_path)

    data = JSON.parse(File.read(token_path))
    new(
      text: data.fetch("text"),
      voice: data.fetch("voice").to_sym,
      style: data.fetch("style").to_sym,
      rate: data["rate"],
      pitch: data["pitch"],
      voice_locked: data.fetch("voice_locked", false),
      style_locked: data.fetch("style_locked", false)
    )
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "TtsJob.find", job_id: job_id.to_s)
    nil
  end

  def self.cancel(job_id)
    return false unless job_id.to_s.match?(/\A[0-9a-f]{32}\z/)

    token_path = CACHE_DIR.join("#{job_id}.job")
    return false unless File.file?(token_path)

    FileUtils.mkdir_p(CACHE_DIR)
    %w[.mp3 .job .err].each do |ext|
      path = CACHE_DIR.join("#{job_id}#{ext}")
      File.delete(path) if File.exist?(path)
    end
    true
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "TtsJob.cancel", job_id: job_id.to_s)
    false
  end

  attr_reader :job_id

  def initialize(text:, voice:, style:, rate: nil, pitch: nil, voice_locked: false, style_locked: false, bus: nil)
    @text = text.to_s
    @voice = voice.to_sym
    @style = style.to_sym
    @rate = rate
    @pitch = pitch
    @voice_locked = voice_locked
    @style_locked = style_locked
    @bus = bus
    @fingerprint = Digest::SHA256.hexdigest("#{@voice}|#{@style}|#{@rate}|#{@pitch}|#{@text}")
    @job_id = @fingerprint[0, 32]
  end

  def ready?
    File.file?(cache_path) && !File.zero?(cache_path)
  end

  def failed?
    File.file?(error_path)
  end

  def pending?
    !ready? && !failed?
  end

  def error
    return nil unless failed?

    File.read(error_path).strip
  end

  def bytes
    File.binread(cache_path) if ready?
  end

  def bytes_available
    return 0 unless File.file?(cache_path)

    File.size(cache_path)
  end

  def partial_bytes
    avail = bytes_available
    return nil if avail.zero?

    File.binread(cache_path, avail)
  end

  def perform
    return if ready?

    FileUtils.mkdir_p(CACHE_DIR)
    File.delete(error_path) if File.exist?(error_path)
    File.write(
      CACHE_DIR.join("#{@job_id}.job"),
      JSON.generate(
        text: @text,
        voice: @voice,
        style: @style,
        rate: @rate,
        pitch: @pitch,
        voice_locked: @voice_locked,
        style_locked: @style_locked
      )
    )
    ok = synthesize_streaming_to_cache
    unless ok && bytes_available > 0
      message = Master::Voice::Speech.last_error || "synthesis produced empty audio"
      record_failure(message)
      return
    end

    write_meta_json
    @bus&.publish("tts:job_complete", job_id: @job_id, ready: true)
  rescue StandardError => e
    record_failure(e.message)
  end

  private

  def synthesize_streaming_to_cache
    Master::Voice::Speech.synthesize_streaming_to_file(
      @text,
      output_path: cache_path.to_s,
      voice: @voice,
      style: @style,
      rate: @rate,
      pitch: @pitch,
      voice_locked: @voice_locked,
      style_locked: @style_locked,
      on_chunk: method(:publish_chunk_progress)
    )
  end

  def publish_chunk_progress(bytes)
    return unless bytes >= 8192

    @bus&.publish("tts:chunk:bytes", job_id: @job_id, bytes: bytes)
  end

  def cache_path
    CACHE_DIR.join("#{@job_id}.mp3")
  end

  def meta_path
    CACHE_DIR.join("#{@job_id}.meta.json")
  end

  def meta
    return nil unless File.file?(meta_path)

    JSON.parse(File.read(meta_path))
  rescue StandardError
    nil
  end

  def error_path
    CACHE_DIR.join("#{@job_id}.err")
  end

  def write_meta_json
    stream = Master::Voice::Expression.viseme_stream(@text, style: @style, rate: @rate)
    File.write(
      meta_path,
      JSON.generate(
        job_id: @job_id,
        voice: @voice.to_s,
        style: @style.to_s,
        **stream.transform_keys(&:to_s)
      )
    )
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "TtsJob.write_meta_json", job_id: @job_id)
  end

  def record_failure(message)
    FileUtils.mkdir_p(CACHE_DIR)
    File.write(error_path, message.to_s)
    File.delete(cache_path) if File.exist?(cache_path)
    @bus&.publish("tts:job_error", job_id: @job_id, error: message)
  end
end