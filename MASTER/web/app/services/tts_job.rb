# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

class TtsJob
  CACHE_DIR = Rails.root.join("tmp", "tts_cache")

  def self.enqueue(text:, voice:, style:, rate: nil, pitch: nil, bus: nil)
    job = new(text: text, voice: voice, style: style, rate: rate, pitch: pitch, bus: bus)
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
      pitch: data["pitch"]
    )
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "TtsJob.find", job_id: job_id.to_s)
    nil
  end

  attr_reader :job_id

  def initialize(text:, voice:, style:, rate: nil, pitch: nil, bus: nil)
    @text = text.to_s
    @voice = voice.to_sym
    @style = style.to_sym
    @rate = rate
    @pitch = pitch
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

  def perform
    return if ready?

    FileUtils.mkdir_p(CACHE_DIR)
    File.delete(error_path) if File.exist?(error_path)
    File.write(
      CACHE_DIR.join("#{@job_id}.job"),
      JSON.generate(text: @text, voice: @voice, style: @style, rate: @rate, pitch: @pitch)
    )
    data = Master::Voice::Speech.synthesize_bytes(@text, voice: @voice, style: @style, rate: @rate, pitch: @pitch)
    if data.nil? || data.empty?
      message = Master::Voice::Speech.last_error || "synthesis produced empty audio"
      record_failure(message)
      return
    end

    File.binwrite(cache_path, data)
    @bus&.publish("tts:job_complete", job_id: @job_id, ready: true)
  rescue StandardError => e
    record_failure(e.message)
  end

  private

  def cache_path
    CACHE_DIR.join("#{@job_id}.mp3")
  end

  def error_path
    CACHE_DIR.join("#{@job_id}.err")
  end

  def record_failure(message)
    FileUtils.mkdir_p(CACHE_DIR)
    File.write(error_path, message.to_s)
    File.delete(cache_path) if File.exist?(cache_path)
    @bus&.publish("tts:job_error", job_id: @job_id, error: message)
  end
end