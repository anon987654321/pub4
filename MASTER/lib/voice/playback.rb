# frozen_string_literal: true

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

      # Past this a reply is a document, not an utterance, and reading it aloud
      # outlasts the user's patience by minutes.
      MAX_SPOKEN_CHARS = 3_000

      @queue = nil
      @worker = nil
      @lock = Mutex.new
      @warned = false

      module_function

      def player
        return @player if defined?(@player) && !@player.nil?

        name = PLAYERS.keys.find { |candidate| which(candidate) }
        @player = name && [name, PLAYERS.fetch(name)]
      end

      def which(cmd)
        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          path = File.join(dir, cmd)
          File.executable?(path) && !File.directory?(path)
        end
      end

      def available?
        !player.nil?
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
        return if str.empty? || str.length > MAX_SPOKEN_CHARS
        return unless enabled?

        unless available?
          warn_once("no audio player found (looked for #{PLAYERS.keys.join(', ')}) — replies stay silent")
          return
        end

        ensure_worker.push(str)
        nil
      end

      def ensure_worker
        @lock.synchronize do
          @queue ||= Queue.new
          @worker ||= Thread.new { drain }
          @worker[:name] = "voice-playback"
          @queue
        end
      end

      def drain
        while (text = @queue.pop)
          path = synthesize(text)
          next unless path

          play(path)
          File.delete(path) if path.start_with?("/tmp/m_tts_") && File.exist?(path)
        end
      end

      # Speech already defaults to Osman, because DEFAULT_VOICE is
      # Policy.single_voice_key. The tempo is the part that does not come for
      # free: with no rate or pitch passed, Speech falls back to STYLES[:calm]
      # at -6% and -20Hz, which is Osman's voice read at someone else's pace.
      # The web does not use that table — it reads default_rate and
      # default_pitch out of Policy.browser_payload and applies them in the
      # page. Passing the same two values is what makes the CLI and the web one
      # speaker rather than two that share a name.
      #
      # Policy.default_volume is deliberately not passed: nothing consumes a
      # volume anywhere in the synthesis path, browser_payload does not carry
      # it either, and inventing a fourth reader for it here would change how
      # MASTER sounds on an assumption rather than a decision.
      def synthesize(text)
        Speech.synthesize(text, rate: Policy.default_rate, pitch: Policy.default_pitch)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.synthesize")
        nil
      end

      def play(path)
        return unless File.exist?(path)

        name, args = player
        system(name, *args, path, out: File::NULL, err: File::NULL)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Voice::Playback.play")
      end

      # A missing player is a real condition the operator can fix, so it is said
      # once. Saying it after every reply would be its own kind of noise.
      def warn_once(message)
        @lock.synchronize do
          next if @warned

          @warned = true
          warn "voice: #{message}"
        end
      end
    end
  end
end
