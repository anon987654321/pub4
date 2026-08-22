# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

class TtsJob
  CACHE_DIR = Rails.root.join("tmp", "tts_cache")

  # Lower number is spoken sooner. The client already ranks its playback lanes
  # error > response > nudge (face_speech_runtime.js), but this queue was plain
  # FIFO, so an idle-loop nudge enqueued a moment before a reply was SYNTHESIZED
  # first and the reply waited behind it. Ranking playback without ranking
  # synthesis only moves the stall earlier in the pipeline.
  PRIORITIES = { "error" => 0, "response" => 1, "nudge" => 2 }.freeze
  DEFAULT_PRIORITY = PRIORITIES.fetch("response")

  @queue_mutex = Mutex.new
  # Workers used to spin on `sleep 0.25` when the queue was empty, which is the
  # common case for the first sentence of a reply: nothing else is in flight, so
  # the job waited up to 250ms for a worker to wake before synthesis even began.
  # A condition variable costs nothing and wakes on enqueue.
  @queue_ready = ConditionVariable.new
  @materialize_mutex = Mutex.new
  @materializing = {}
  @queue = []
  @workers = []

  def self.enqueue(text:, voice:, style:, rate: nil, pitch: nil, voice_locked: false, style_locked: false, bus: nil,
                   lane: "response", conversation: nil)
    job = new(
      text:,
      voice:,
      style:,
      rate:,
      pitch:,
      voice_locked:,
      style_locked:,
      bus:,
      conversation:,
    )
    return job if job.ready?

    # Write the token file now, before the client can start polling — perform()
    # used to be the only writer, but it only runs once the background worker
    # thread dequeues this job, which can be seconds after enqueue if other
    # jobs are ahead of it. In that window, GET /chat/tts/status found no token
    # file, returned a real 404 (not 202 pending), and the client's pollTTSJob
    # treats any non-202 as fatal and throws immediately — silently falling
    # back to the browser's native speechSynthesis (a different, robotic voice
    # per OS/browser). Writing the token at enqueue time closes that race.
    job.write_token
    rank = PRIORITIES.fetch(lane.to_s, DEFAULT_PRIORITY)
    @queue_mutex.synchronize do
      unless @queue.any? { |queued| queued[:job].job_id == job.job_id }
        # Stable insert: ahead of everything strictly lower priority, behind
        # everything of equal priority, so same-lane order is still arrival
        # order and a reply's sentences cannot overtake each other.
        at = @queue.index { |queued| queued[:rank] > rank } || @queue.size
        @queue.insert(at, { job:, rank: })
      end
      spawn_workers_locked!
      @queue_ready.signal
    end
    job
  end

  # One worker thread per daemon pool slot -- a single worker serialized every
  # job through one queue regardless of pool_size, so a reply queued behind a
  # few other chunks legitimately took 30-60s+ even with idle daemon sockets
  # sitting unused. Threads (not processes) are fine here: each job's real
  # work is a blocking socket read waiting on Microsoft's Edge TTS endpoint,
  # which releases the GVL, so N threads genuinely overlap N in-flight
  # network round-trips even on a 1-vCPU box.
  def self.spawn_workers_locked!
    @workers.reject!(&:alive?)
    wanted = [Master::Voice::TtsSupervisor.pool_size, 1].max
    return if @workers.size >= wanted

    (wanted - @workers.size).times { @workers << spawn_worker }
  end

  def self.spawn_worker
    Thread.new do
      Thread.current.name = "tts-job-worker"
      Thread.current.report_on_exception = false
      loop do
        entry = @queue_mutex.synchronize do
          # wait releases the mutex and re-acquires on signal, so an enqueue
          # wakes this thread immediately instead of it noticing up to 250ms
          # later. The timeout is a safety net against a missed signal, not the
          # normal path.
          @queue_ready.wait(@queue_mutex, 5) while @queue.empty?
          @queue.shift
        end
        materialize!(entry[:job]) if entry
      end
    end
  end

  # Falcon's async reactor often never schedules short-lived enqueue threads, so
  # jobs sat at .job forever while the client polled 202 pending. Run synthesis
  # on the status/stream poll path as well; one mutex per job_id avoids doubles.
  def self.materialize!(job)
    return job unless job&.pending?

    @materialize_mutex.synchronize do
      return job if job.ready? || job.failed?
      return job if @materializing[job.job_id]

      @materializing[job.job_id] = true
    end
    job.perform
    job
  ensure
    @materialize_mutex.synchronize { @materializing.delete(job.job_id) if job }
  end

  def self.ensure_worker!
    @queue_mutex.synchronize { spawn_workers_locked! }
  end

  def self.find(job_id)
    data = read_token(job_id)
    return unless data

    new(
      text: data.fetch("text"),
      voice: data.fetch("voice").to_sym,
      style: data.fetch("style").to_sym,
      rate: data["rate"],
      pitch: data["pitch"],
      voice_locked: data.fetch("voice_locked", false),
      style_locked: data.fetch("style_locked", false),
      conversation: data["conversation"],
    )
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "TtsJob.find", job_id: job_id.to_s)
    nil
  end

  def self.owned?(job_id, conversation)
    data = read_token(job_id)
    return false unless data

    stored = data["conversation"].to_s
    stored.present? && stored == conversation.to_s
  end

  def self.cancel(job_id, conversation: nil)
    return false unless owned?(job_id, conversation)

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

  def self.read_token(job_id)
    return unless job_id.to_s.match?(/\A[0-9a-f]{32}\z/)

    token_path = CACHE_DIR.join("#{job_id}.job")
    return unless File.file?(token_path)

    JSON.parse(File.read(token_path))
  end
  # The spawn pair is not API — the queue runs itself. ensure_worker! and
  # materialize! ARE: master_container.rb boots the worker through one and
  # tts_controller.rb runs synthesis on the poll path through the other, and
  # privatizing them took ai.brgen.no down on 2026-08-22 — the caller grep
  # that said otherwise was wrong, and no local test boots the container.
  private_class_method :read_token, :spawn_workers_locked!, :spawn_worker

  attr_reader :job_id

  def initialize(text:, voice:, style:, rate: nil, pitch: nil, voice_locked: false, style_locked: false, bus: nil,
                 conversation: nil)
    @text = text.to_s
    @voice = voice.to_sym
    @style = style.to_sym
    @rate = rate
    @pitch = pitch
    @voice_locked = voice_locked
    @style_locked = style_locked
    @bus = bus
    @conversation = conversation.to_s.presence
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
    return unless failed?

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
    return if avail.zero?

    File.binread(cache_path, avail)
  end

  def write_token
    FileUtils.mkdir_p(CACHE_DIR)
    path = CACHE_DIR.join("#{@job_id}.job")
    existing = File.file?(path) ? (JSON.parse(File.read(path)) rescue {}) : {}
    conversation = existing["conversation"].presence || @conversation
    File.write(
      path,
      JSON.generate(
        text: @text,
        voice: @voice,
        style: @style,
        rate: @rate,
        pitch: @pitch,
        voice_locked: @voice_locked,
        style_locked: @style_locked,
        conversation: conversation,
      ),
    )
  end

  def perform
    return if ready?

    write_token
    File.delete(error_path) if File.exist?(error_path)
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

  def meta
    return unless File.file?(meta_path)

    JSON.parse(File.read(meta_path))
  rescue StandardError => e
    Master::Ground::Swallow.log(e, context: "TtsJob.meta_parse")
    nil
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
      on_chunk: method(:publish_chunk_progress),
    )
  end

  def publish_chunk_progress(bytes)
    return unless bytes >= 8192

    @bus&.publish("tts:chunk:bytes", job_id: @job_id, bytes:)
  end

  def cache_path
    CACHE_DIR.join("#{@job_id}.mp3")
  end

  def meta_path
    CACHE_DIR.join("#{@job_id}.meta.json")
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
        **stream.transform_keys(&:to_s),
      ),
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
