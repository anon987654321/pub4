# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

class TtsJob
  CACHE_DIR = Rails.root.join("tmp", "tts_cache")

  def self.enqueue(text:, voice:, style:, bus: nil)
    job = new(text: text, voice: voice, style: style, bus: bus)
    return job if job.ready?

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
    new(text: data.fetch("text"), voice: data.fetch("voice").to_sym, style: data.fetch("style").to_sym)
  rescue StandardError
    nil
  end

  attr_reader :job_id

  def initialize(text:, voice:, style:, bus: nil)
    @text = text.to_s
    @voice = voice.to_sym
    @style = style.to_sym
    @bus = bus
    @fingerprint = Digest::SHA256.hexdigest("#{@voice}|#{@style}|#{@text}")
    @job_id = @fingerprint[0, 32]
  end

  def cache_path
    CACHE_DIR.join("#{@job_id}.mp3")
  end

  def ready?
    File.file?(cache_path)
  end

  def bytes
    File.binread(cache_path) if ready?
  end

  def perform
    return if ready?

    FileUtils.mkdir_p(CACHE_DIR)
    File.write(CACHE_DIR.join("#{@job_id}.job"), JSON.generate(text: @text, voice: @voice, style: @style))
    data = Master::Voice::Speech.synthesize_bytes(@text, voice: @voice, style: @style)
    File.binwrite(cache_path, data) if data && !data.empty?
    @bus&.publish("tts:job_complete", job_id: @job_id, ready: ready?)
  rescue StandardError => e
    @bus&.publish("tts:job_error", job_id: @job_id, error: e.message)
  end
end
