# frozen_string_literal: true

require "open3"
require "set"
require_relative "../ops/process_spawn"

module Master
  module Voice
    # Plays what Speech synthesises.
    #
    # Speech returns a path to an mp3 and the CLI never opened it, so the whole
    # Edge TTS stack — worker pool, socket daemon, the supervisor started at
    # boot in Boot::MasterBoot — synthesised every reply into a file nobody
    # read. This is the reader.
    #
    # Synthesis is a network round trip, so it happens on one background worker
    # rather than between the reply and the next prompt. One worker, not a pool:
    # replies must be spoken in the order they were printed, and two voices at
    # once is worse than a pause.
    module Playback
      # afplay is macOS. The deploy host has no audio hardware, so the others
      # are for a workstation that is not a Mac, not for vm23 — see the note in
      # Engines.synth_edge_melodic, which relies on the same absence.
      #
      # Performance never changes the synthesised signal. Prefetch only overlaps
      # an already-declared TTS synthesis with playback of the preceding file.
      # Transcendent stays one utterance so its existing melody/phrase plan is
      # never split into independently generated musical fragments.
      PLAYERS = {
        "afplay" => [],
        "sox" => %w[-q],
        "ffplay" => %w[-nodisp -autoexit -loglevel quiet],
        "mpv" => %w[--no-video --really-quiet],
        "aucat" => %w[-i],
      }.freeze

      # A line already waiting to be spoken, or spoken a moment ago, is not
      # spoken again: two paths reach this door with one reply — the result
      # display and the bridge summary — and a retried synthesis said it a
      # third time. A deliberate repeat past the echo window still speaks,
      # because asking the same question twice is a thing a person does.
      ECHO_WINDOW_S = 20

      @queue = nil
      @worker = nil
      @lock = Mutex.new
      @warned = false
      @pending = nil
      @last_said = nil
      @last_at = 0.0
      @generation = 0
      @playing_pid = nil
      @job_generations = {}

      module_function

      def last_error = @last_error

      def player
        return @player if defined?(@player) && !@player.nil?

        name, path = PLAYERS.keys.filter_map do |candidate|
          path = which(candidate)
          [candidate, path] if path
        end.first
        @player = name && [path, PLAYERS.fetch(name)]
      end

      def which(cmd)
        candidates = [
          "/opt/homebrew/bin/#{cmd}",
          "/usr/local/bin/#{cmd}",
          *ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, cmd) },
        ]
        candidates.uniq.find { |path| File.executable?(path) && !File.directory?(path) }
      end

      def available?
        !player.nil? || native_say_available? || android_audio_available?
      end

      def android_audio_available?
        Device::Audio.available?
      rescue NameError
        false
      end

      def native_say_available?
        which("say") != nil
      end

      # Speaking is for a person sitting at a terminal. A pipe, a test, a CI
      # run and the deploy host all get silence, and none of them should pay
      # for a synthesis they cannot hear.
      def enabled?
        return false if ENV["MASTER_CLI_SPEAK"] == "0"
        return false if ENV["MASTER_SKIP_TTS"] == "1"
        return false if ENV["CI"]
        return false unless $stdout.isatty

        true
      end

      def speak(text, priority: :reply)
        str = text.to_s.strip
        return if str.empty?
        return unless enabled?

        unless available?
          warn_once("no audio output found (no player or native speech) — replies stay silent")
          return
        end

        return if echo?(str)

        # Conversational replies own the speaker. Diagnostic/council speech can
        # stay queued, but a reply starts a fresh playback generation so stale
        # audio is stopped before the answer enters the queue.
        generation = priority.to_sym == :reply ? begin_reply_generation! : current_generation
        parts = transcendent_mode? ? [str] : Speech.chunks(str)
        parts = [str] if parts.empty?
        reply_voice = Speech.voice_for_text(str)
        reply_style = transcendent_mode? ? :auto : Speech.infer_style(str, fallback: Speech.default_style)
        queue = ensure_queue
        jobs = parts.each_with_index.map do |part, index|
          [str, part, index == parts.size - 1, reply_voice, reply_style, nil, nil, generation]
        end

        @lock.synchronize do
          jobs.each do |job|
            break unless generation == @generation

            @job_generations[job.object_id] = generation
            queue << job
          end
        end
        start_worker!
        nil
      end



      # Session-owned enqueue path. Callers can provide a generation so
      # interrupted work cannot reach the speaker later. When generation is
      # omitted, Playback uses its current cancellation generation.
      def enqueue(text, generation: nil, voice: nil, style: nil, rate: nil, pitch: nil, last: true)
        str = text.to_s.strip
        return false if str.empty?

        queue = ensure_queue
        accepted = @lock.synchronize do
          current = generation || @generation
          next false unless current == @generation

          queue << {
            text: str,
            voice:,
            style:,
            rate:,
            pitch:,
            last:,
            generation: current,
          }
          true
        end
        start_worker!
        accepted
      end

      # Synchronous path for an operator-facing hardware test. Normal replies
      # remain asynchronous; a test must not report "queued" and leave the
      # process to decide whether the worker ever reached the speaker.
      def speak_now(text)
        str = text.to_s.strip
        return false if str.empty?
        return false unless enabled?

        unless available?
          warn_once("no audio player found (looked for #{PLAYERS.keys.join(', ')}) — replies stay silent")
          return false
        end

        path = synthesize(str)
        unless path
          ok = android_speak(str) || native_say(str)
          warn_once("synthesis failed#{Speech.last_error ? ": #{Speech.last_error}" : ""}") unless ok
          spoken(str) if ok
          return ok
        end

        ok = play(path)
        ok = android_speak(str) unless ok
        ok = native_say(str) unless ok
        unless ok
          warn_once("audio playback failed — #{player&.first || "no player or native speech"}")
        else
          spoken(str)
        end
        ok
      rescue StandardError => e
        warn_once("voice test failed — #{e.class}: #{e.message}")
        false
      ensure
        File.delete(path) if defined?(path) && path && path.start_with?("/tmp/m_tts_") && File.exist?(path)
      end

      # Under the lock the queue is built with, so a push and a drain cannot
      # disagree about what is pending.
      # A voice-first session must be interruptible at the audio boundary, not only
      # at the turn/process boundary. In-flight synthesis may finish in the background,
      # but its generation becomes stale and therefore can never reach the speaker.
      def begin_generation!
        @lock.synchronize { @generation += 1 }
      end

      # One answer must own the speaker. Cancel older log/council audio at the
      # process boundary, but preserve the echo memory so the same reply cannot
      # immediately be re-enqueued by another presentation path.
      def begin_reply_generation!
        @lock.synchronize do
          @generation += 1
          @queue&.clear
          @job_generations.clear
          terminate_player_locked if @playing_pid
          @generation
        end
      end

      def interrupt!(_reason = nil)
        @lock.synchronize do
          @generation += 1
          @queue&.clear
          @job_generations.clear
          @pending&.clear
          @last_said = nil
          terminate_player_locked if @playing_pid
        end
        Device::Audio.stop if Device::Audio.media_player_available?
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.interrupt")
        false
      end

      def echo?(str)
        @lock.synchronize do
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @pending ||= Set.new
          next true if @pending.include?(str)
          next true if str == @last_said && now - @last_at < ECHO_WINDOW_S

          @pending << str
          false
        end
      end

      def spoken(text)
        @lock.synchronize do
          @pending&.delete(text)
          @last_error = nil
          @last_said = text
          @last_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      def ensure_queue
        @lock.synchronize do
          @queue ||= Queue.new
          @pending ||= Set.new
          @queue
        end
      end

      def start_worker!
        @lock.synchronize do
          return @worker if @worker&.alive?

          @worker = Thread.new { drain }
          @worker[:name] = "voice-playback"
        end
      end

      def ensure_worker
        ensure_queue
        start_worker!
      end

      def drain
        while (job = @queue.pop)
          process_job_sequence(job)
        end
      end

      def process_job_sequence(current)
        prepared_current = nil

        loop do
          following = dequeue_nowait
          prepared_following = start_prefetch(following)

          prepared_current ||= prepare_job(current)
          consume_prepared(prepared_current)
          cleanup_prepared(prepared_current)

          current = following
          prepared_current = await_prefetch(prepared_following)
          break unless current
        end
      end

      def dequeue_nowait
        @queue.pop(true)
      rescue ThreadError
        nil
      end

      def start_prefetch(job)
        return unless job
        return unless prefetch_enabled?

        result_queue = Queue.new
        thread = Thread.new do
          Thread.current[:name] = "voice-prefetch"
          result_queue << prepare_job(job, live: false)
        rescue StandardError => e
          result_queue << prepare_job_failure(job, e)
        end
        PrefetchedAudio.new(thread:, result_queue:)
      rescue StandardError => e
        warn_once("voice prefetch failed to start — #{e.class}: #{e.message}")
        nil
      end

      def await_prefetch(prefetched)
        return nil unless prefetched

        prepared = prefetched.result_queue.pop
        prefetched.thread.join
        prepared
      rescue StandardError => e
        warn_once("voice prefetch failed — #{e.class}: #{e.message}")
        nil
      end

      def prepare_job_failure(job, error)
        warn_once("voice prefetch synthesis failed — #{error.class}: #{error.message}")
        values = decode_job(job)
        PreparedAudio.new(**values, path: nil)
      end

      # Live streaming needs a player that reads a pipe — ffplay does, afplay
      # cannot — the framed daemon wire, and the classic mode: Transcendent owns
      # its whole utterance, melody and phrase rhythm included, and is never
      # piped piecemeal (MASTER_TTS_STREAM=0 turns the lane off).
      def stream_playback_ready?
        return false if ENV["MASTER_TTS_STREAM"] == "0"
        return false if transcendent_mode?
        return false unless Speech.edge_tts_available?
        return false unless Speech.stream_wire_enabled?
        return false unless Speech.worker_executable?
        !stream_player.nil?
      end

      def stream_player
        path = which("ffplay")
        path && [path, PLAYERS.fetch("ffplay")]
      end

      def prepare_stream_job(values)
        return unless stream_playback_ready?

        voice_name, style_config = stream_voice_config(values)
        thread = Thread.new do
          Thread.current[:name] = "voice-stream"
          Thread.current[:ok] = stream_utterance(values, voice_name, style_config)
        end
        StreamingPrepared.new(
          job: values[:job],
          text: values[:text],
          part: values[:part],
          last: values[:last],
          generation: values[:generation],
          thread:,
        )
      rescue StandardError => e
        warn_once("voice stream prepare failed — #{e.class}: #{e.message}")
        nil
      end

      # Mirrors Playback.synthesize's resolution: the policy tempo when the
      # caller says nothing, style validated through resolve_voice_and_style.
      def stream_voice_config(values)
        voice = Speech.resolve_voice(values[:voice] || Speech.voice_for_text(values[:part]))
        voice, style_config = Speech.resolve_voice_and_style(
          values[:part],
          voice:,
          style: values[:style] || Speech.default_style,
          rate: values[:rate] || Policy.default_rate,
          pitch: values[:pitch] || Policy.default_pitch,
          style_locked: true,
        )
        [Speech::VOICES.fetch(voice, Speech::VOICES[Speech.default_voice]), style_config]
      end

      # ffplay demuxes mp3 straight from a non-seekable stdin (-f forces the
      # demuxer), applies the voice.yml post_chain with -af — the same chain
      # Speech#shaped runs for the afplay path, so streaming never changes how
      # a reply sounds — and exits on its own once stdin ends. Interrupt kills
      # it the same way it kills afplay: through @playing_pid.
      def stream_cmd(player_path, player_args)
        cmd = [player_path, *player_args, "-f", "mp3"]
        chain = Policy.post_chain
        cmd += ["-af", chain] if chain && !chain.empty?
        cmd << "pipe:0"
        cmd
      end

      # One stream through one player process: register the player pid so
      # interrupt can kill it, copy the wire into its stdin, keep the stream
      # result so the caller can resynthesise anything truncated.
      StreamOutcome = Data.define(:ok, :played_bytes)

      def pump_stream_pipe(cmd, spawn_opts, values, voice_name, style_config)
        generation = values[:generation]
        outcome = StreamOutcome.new(ok: false, played_bytes: 0)
        Open3.popen3(*cmd, **spawn_opts) do |stdin, _o, _e, wait_thr|
          active = generation_active?(generation)
          @lock.synchronize { @playing_pid = wait_thr.pid if active }
          begin
            stale = -> { !generation_active?(generation) }
            stream = Speech.stream_edge_to_io(
              text: values[:part],
              voice_name:,
              style_config:,
              io: stdin,
              stale_test: stale,
            )
            outcome = StreamOutcome.new(ok: stream.ok, played_bytes: stream.bytes)
          ensure
            stdin.close
            outcome = StreamOutcome.new(
              ok: outcome.ok && wait_thr.value.success?,
              played_bytes: outcome.played_bytes,
            )
            @lock.synchronize { @playing_pid = nil if @playing_pid == wait_thr.pid }
          end
        end
        outcome
      end

      def stream_utterance(values, voice_name, style_config)
        player_path, player_args = stream_player
        return false unless player_path

        spawn_opts = Master::Ops::ProcessSpawn.options(out: File::NULL, err: File::NULL)
        cmd = stream_cmd(player_path, player_args)
        outcome = pump_stream_pipe(cmd, spawn_opts, values, voice_name, style_config)
        return true if outcome.ok

        # Never replay an utterance after bytes have reached the speaker. A
        # truncated stream used to resynthesize the entire sentence after the
        # partial stream had already been heard, producing the delayed second
        # voice/overlap reported at the terminal. A stream with no emitted audio
        # is safe to replace; a partially heard stream is a failed utterance.
        return stream_fallback(values) if outcome.played_bytes.zero? && generation_active?(values[:generation])

        false
      end

      # A stream truncated mid-sentence is dropped before playback, so the
      # whole utterance is recovered the expensive way rather than half-spoken.
      def stream_fallback(values)
        warn_once("voice stream truncated, resynthesising")
        path = synthesize(
          values[:part],
          voice: values[:voice],
          style: values[:style],
          rate: values[:rate],
          pitch: values[:pitch],
        )
        return false unless path

        play_or_fallback(path, values[:text], generation: values[:generation], voice: values[:voice])
      ensure
        delete_temp_audio(path) if defined?(path) && path
      end

      def prefetch_enabled?
        return false unless ENV.fetch("MASTER_TTS_PREFETCH", "1") != "0"
        return false unless Speech.synthesis_mode.to_s == "classic"

        TtsSupervisor.pool_size > 1
      rescue StandardError
        false
      end

      def prepare_job(job, live: true)
        @lock.synchronize { @job_generations.delete(job.object_id) }
        values = decode_job(job)
        return PreparedAudio.new(**values, path: nil) unless generation_active?(values[:generation])

        stream_prepared = prepare_stream_job(values) if live
        return stream_prepared if stream_prepared

        synthesize_job(values)
      rescue StandardError => e
        warn_once("playback synthesis failed — #{e.class}: #{e.message}")
        PreparedAudio.new(**(values || decode_job(job)), path: nil)
      end

      # The whole-file lane behind the live one: make the audio, then drop it
      # the moment the generation died under us instead of speaking stale text.
      def synthesize_job(values)
        path = synthesize(
          values[:part],
          voice: values[:voice],
          style: values[:style],
          rate: values[:rate],
          pitch: values[:pitch],
        )
        active = path && generation_active?(values[:generation])
        delete_temp_audio(path) if path && !active
        PreparedAudio.new(**values, path: active ? path : nil)
      end

      def decode_job(job)
        if job.is_a?(Hash)
          {
            job:,
            text: job[:text],
            part: job[:text],
            last: job[:last],
            voice: job[:voice] || Speech.voice_for_text(job[:text]),
            style: job[:style] || Speech.infer_style(job[:text], fallback: Speech.default_style),
            rate: job[:rate],
            pitch: job[:pitch],
            generation: job[:generation] || current_generation,
          }
        elsif job.is_a?(Array)
          {
            job:,
            text: job[0],
            part: job[1],
            last: job[2],
            voice: job[3],
            style: job[4],
            rate: job[5],
            pitch: job[6],
            generation: job[7] || current_generation,
          }
        else
          {
            job:,
            text: job,
            part: job,
            last: true,
            voice: Speech.voice_for_text(job),
            style: Speech.infer_style(job, fallback: Speech.default_style),
            rate: nil,
            pitch: nil,
            generation: current_generation,
          }
        end
      end

      def consume_prepared(prepared)
        return consume_stream_prepared(prepared) if prepared.is_a?(StreamingPrepared)
        return false unless prepared&.path && generation_active?(prepared.generation)

        unless play_or_fallback(prepared.path, prepared.text, generation: prepared.generation, voice: prepared.voice)
          return playback_failed!
        end
        spoken(prepared.text) if prepared.last && generation_active?(prepared.generation)
        true
      end

      def playback_failed!
        warn_once("audio playback failed — #{player&.first || "no player or native speech"}")
        false
      end

      # A streamed utterance plays while it synthesises: the prepare thread
      # already owns the player process, joining it is the whole consumption.
      def consume_stream_prepared(prepared)
        return false unless prepared.thread

        prepared.thread.join
        ok = prepared.thread[:ok] == true
        if ok && prepared.last && generation_active?(prepared.generation)
          spoken(prepared.text)
        end
        ok
      end

      def delete_temp_audio(path)
        return unless path.to_s.start_with?("/tmp/m_tts_")
        return unless File.exist?(path)

        File.delete(path)
      rescue StandardError
        nil
      end

      def cleanup_prepared(prepared)
        return unless prepared.respond_to?(:path)

        path = prepared.path
        return unless path
        return unless path.start_with?("/tmp/m_tts_")
        return unless File.exist?(path)

        File.delete(path)
      rescue StandardError
        nil
      end

      PrefetchedAudio = Data.define(
        :thread,
        :result_queue,
      )

      # One utterance whose synthesis and playback overlap — the prepare thread
      # holds the player process and pours socket frames into its stdin.
      StreamingPrepared = Data.define(
        :job,
        :text,
        :part,
        :last,
        :generation,
        :thread,
      )

      PreparedAudio = Data.define(
        :job,
        :text,
        :part,
        :last,
        :voice,
        :style,
        :rate,
        :pitch,
        :generation,
        :path,
      )

      # Speech already defaults to the policy voice, because DEFAULT_VOICE is
      # Policy.single_voice_key. The tempo is the part that does not come for
      # free: with no rate or pitch passed, Speech falls back to STYLES[:calm]
      # at -6% and -20Hz, which is the policy voice read at someone else's pace.
      # The web does not use that table — it reads default_rate and
      # default_pitch out of Policy.browser_payload and applies them in the
      # page. Passing the same two values is what makes the CLI and the web one
      # speaker rather than two that share a name.
      #
      # Policy.default_volume is deliberately not passed: nothing consumes a
      # volume anywhere in the synthesis path, browser_payload does not carry
      # it either, and inventing a fourth reader for it here would change how
      # MASTER sounds on an assumption rather than a decision.
      def synthesize(text, voice: nil, style: nil, rate: nil, pitch: nil)
        dynamic = transcendent_mode?
        locked_style = style && style != :auto
        Speech.synthesize(
          text,
          voice:,
          style: dynamic && !locked_style ? :auto : (style || Speech.default_style),
          rate: dynamic ? rate : (rate || Policy.default_rate),
          pitch: dynamic ? pitch : (pitch || Policy.default_pitch),
          voice_locked: true,
          style_locked: !dynamic || locked_style || rate || pitch,
        )
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.synthesize")
        nil
      end

      # A failed player is recoverable when the policy-mapped native voice exists.
      # Never bypass synthesis failure itself; fallback begins only after a player error.
      def play_or_fallback(path, text, generation:, voice: nil)
        @lock.synchronize { @last_player_attempted = false }
        return true if play(path, generation:)
        return false unless generation_active?(generation)
        return false if @lock.synchronize { @last_player_attempted }

        native_say(text, voice:)
      end

      def android_speak(text)
        return false unless android_audio_available?

        Device::Audio.speak(text)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.android_speak")
        false
      end

      def native_say(text, voice: nil)
        return false unless native_say_available?

        voice = Speech.resolve_voice(voice || Speech.voice_for_text(text)).to_sym
        mac_voice = Engines::MACOS_VOICE_FALLBACKS[voice]
        return false unless mac_voice

        system("say", "-v", mac_voice, text.to_s, out: File::NULL, err: File::NULL)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.native_say")
        false
      end

      def play(path, generation: current_generation)
        return false unless File.exist?(path)
        return false unless generation_active?(generation)

        if Device::Audio.media_player_available?
          @lock.synchronize { @last_player_attempted = true }
          return Device::Audio.play(path)
        end

        player_candidates(path).each do |name, args|
          break unless generation_active?(generation)

          @lock.synchronize { @last_player_attempted = true }
          pid = Process.spawn(name, *args, path, **Master::Ops::ProcessSpawn.options(out: File::NULL, err: File::NULL))
          @lock.synchronize { @playing_pid = pid if generation_active?(generation) }
          begin
            return true if Process.wait(pid).success?
          rescue Errno::ESRCH, Errno::ECHILD
            next
          ensure
            @lock.synchronize { @playing_pid = nil if @playing_pid == pid }
          end
        end
        false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.play")
        false
      end

      def player_candidates(_path)
        preferred = player
        fallback = PLAYERS.keys.filter_map do |candidate|
          path = which(candidate)
          [path, PLAYERS.fetch(candidate)] if path
        end
        [preferred, *fallback].compact.uniq
      end

      def transcendent_mode?
        Speech.synthesis_mode.to_s == "transcendent"
      rescue StandardError
        false
      end

      def current_generation
        @lock.synchronize { @generation }
      end

      def generation_active?(generation)
        @lock.synchronize { generation == @generation }
      end

      def terminate_player_locked
        return unless @playing_pid

        Process.kill("TERM", @playing_pid)
        Process.kill("KILL", @playing_pid) rescue nil
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      ensure
        @playing_pid = nil
      end

      # A missing player is a real condition the operator can fix, so it is said
      # once. Saying it after every reply would be its own kind of noise.
      def warn_once(message)
        @lock.synchronize do
          next if @warned

          @warned = true
          if defined?(Master::Trace::Dmesg)
            Master::Trace::Dmesg.once("voice0", message)
          else
            warn "voice0: #{message}"
          end
        end
      end
    end
  end
end
