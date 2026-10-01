# frozen_string_literal: true

require "set"

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
      PLAYERS = {
        "afplay" => [],
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

      def speak(text)
        str = text.to_s.strip
        return if str.empty?
        return unless enabled?

        unless available?
          warn_once("no audio output found (no player or native speech) — replies stay silent")
          return
        end

        queue = ensure_worker
        return if echo?(str)

        # Sentence by sentence, so the first complete thought is heard while
        # the rest is still being synthesised. The reply's voice and style are
        # selected once here and carried through every chunk: a failed later
        # synthesis must never rotate to a second narrator.
        parts = Speech.chunks(str)
        parts = [str] if parts.empty?
        reply_voice = Speech.voice_for_text(str)
        reply_style = Speech.infer_style(str, fallback: Speech.default_style)
        generation = current_generation
        parts.each_with_index do |part, index|
          job = [str, part, index == parts.size - 1, reply_voice, reply_style]
          @lock.synchronize do
            next unless generation == @generation
            @job_generations[job.object_id] = generation
            queue << job
          end
        end
        nil
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
          @last_said = text
          @last_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end

      def ensure_worker
        @lock.synchronize do
          @queue ||= Queue.new
          @pending ||= Set.new
          @worker ||= Thread.new { drain }
          @worker[:name] = "voice-playback"
          @queue
        end
      end

      def drain
        while (job = @queue.pop)
          path = nil
          begin
            text, part, last, voice, style = if job.is_a?(Array)
              [job[0], job[1], job[2], job[3], job[4]]
            else
              [job, job, true, Speech.voice_for_text(job), Speech.infer_style(job, fallback: Speech.default_style)]
            end
            generation = @lock.synchronize { @job_generations.delete(job.object_id) || @generation }
            next unless generation_active?(generation)

            path = synthesize(part, voice:, style:)
            next unless generation_active?(generation)

            unless path
              # Speech already owns its engine fallback. Calling macOS say here
              # with the full reply was a second, unscoped fallback that could
              # switch speaker and replay everything after one failed chunk.
              warn_once("synthesis failed#{Speech.last_error ? ": #{Speech.last_error}" : ""}")
              next
            end

            unless play(path, generation:)
              # Never replace a failed reply audio path with the host's default
              # speech voice. That voice is outside MASTER's policy and can be
              # a different speaker, locale, rate, and engine from the reply.
              warn_once("audio playback failed — #{player&.first || "no player or native speech"}")
            end
            spoken(text) if last && generation_active?(generation)
          rescue StandardError => e
            warn_once("playback worker failed — #{e.class}: #{e.message}")
          ensure
            File.delete(path) if path&.start_with?("/tmp/m_tts_") && File.exist?(path)
          end
        end
      end

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
      def synthesize(text, voice: nil, style: nil)
        Speech.synthesize(
          text,
          voice:,
          style: style || Speech.default_style,
          rate: Policy.default_rate,
          pitch: Policy.default_pitch,
          voice_locked: true,
          style_locked: true,
        )
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.synthesize")
        nil
      end

      def android_speak(text)
        return false unless android_audio_available?

        Device::Audio.speak(text)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.android_speak")
        false
      end

      def native_say(text)
        return false unless native_say_available?

        voice = Speech.voice_for_text(text).to_sym
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
          return Device::Audio.play(path)
        end

        name, args = player
        return false unless name && args

        pid = Process.spawn(name, *args, path, out: File::NULL, err: File::NULL)
        @lock.synchronize { @playing_pid = pid if generation_active?(generation) }
        status = Process.wait(pid)
        status.success?
      rescue Errno::ESRCH, Errno::ECHILD
        false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.play")
        false
      ensure
        @lock.synchronize { @playing_pid = nil if @playing_pid == pid }
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
