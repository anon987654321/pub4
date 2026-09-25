# frozen_string_literal: true

require "digest"
require "securerandom"
require "fileutils"
require "open3"
require "socket"
require "json"
require "timeout"
require_relative "policy"
require_relative "strunk_pass"
require_relative "lexicon"
require_relative "speech_worker"

module Master
  module Voice
    module Speech
      WORKER = File.expand_path("../../bin/tts-worker", __dir__)
      BRIEF_STYLE_WORD_COUNT = 12
      TTS_SOCKET = File.expand_path("../../.master/tts.sock", __dir__)
      ESPEAK_PATHS = %w[/usr/bin/espeak /usr/local/bin/espeak].freeze
      WORKER_TIMEOUT = 45
      # b2cc32b73 tuned WORKER_TIMEOUT for MAX_CHARS=900 on the VPS;
      # MAX_CHARS was later raised 4x (035888e8e) without touching the
      # timeout, so a full-length reply's single unchunked Edge TTS call
      # blew the fixed budget every time -- long replies produced no audio
      # at all. Scale the budget with text length instead of a flat cap.
      WORKER_TIMEOUT_PER_CHAR = 0.05
      WORKER_TIMEOUT_MAX = 180
      # The selftest only boots bundler and requires: 0.26s warm on a dev Mac,
      # measured over three runs. Generous enough for a cold 1-vCPU vm23 under
      # swap, and it is paid once per process because the answer is memoised.
      SELFTEST_TIMEOUT_S = 15
      @last_error = nil
      @selftest_mutex = Mutex.new
      @selftest_stamp = nil
      @selftest_blocker = nil
      # One mutex per pool slot, not one global mutex — ac0146eac serialized
      # synthesis when TtsSupervisor pool_size was 1, so a single mutex was
      # harmless. Pool_size later defaulted to 2 ("for parallel synth"), but
      # the mutex stayed global and silently capped real concurrency at 1
      # regardless of idle pool workers. Sized dynamically so MASTER_TTS_POOL_SIZE=1
      # still gets full serialization.
      @synthesis_mutexes = Hash.new { |h, k| h[k] = Mutex.new }
      @synthesis_rr_mutex = Mutex.new
      @synthesis_rr = 0

      Audio = Struct.new(:bytes, :mime_type, keyword_init: true)

      VOICE_ALIASES = {
        osman: "ms-MY-OsmanNeural",
        ryan: "en-GB-RyanNeural",
        finn: "nb-NO-FinnNeural",
        andrew: "en-US-AndrewNeural",
        guy: "en-US-GuyNeural",
        william: "en-AU-WilliamNeural",
        christopher: "en-US-ChristopherNeural",
        eric: "en-US-EricNeural",
        pernille: "nb-NO-PernilleNeural",
        davis: "en-US-DavisNeural",
        wayne: "en-SG-WayneNeural",
        ezinne: "en-NG-EzinneNeural",
        jenny: "en-US-JennyNeural",
        # One-off read-out mouths for the operator's asks. The rotation never
        # picks these: single_voice stays jenny and rotation is her and
        # christopher, so an alias only speaks when a caller names it and
        # locks it.
        elsa: "it-IT-ElsaNeural",
        prabhat: "en-IN-PrabhatNeural",
        # The 1001 Nights mouth: an Egyptian accent for an Arabic story.
        # One-off read-outs only; the rotation never picks it.
        salma: "ar-EG-SalmaNeural",
        shakir: "ar-EG-ShakirNeural",
      }.freeze

      # Every voice answers to its full Edge name and to its short alias; full
      # names come first, which is the order resolve_voice's reverse lookup reads.
      VOICES = VOICE_ALIASES.values.to_h { |name| [name.to_sym, name] }.merge(VOICE_ALIASES).freeze

      STYLES = {
        neutral: { rate: "+0%", pitch: "+0Hz" },
        normal: { rate: "+0%", pitch: "+0Hz" },
        deep: { rate: "-10%", pitch: "-30Hz" },
        clear: { rate: "+4%", pitch: "+0Hz" },
        calm: { rate: "-6%", pitch: "-20Hz" },
        brief: { rate: "+8%", pitch: "+0Hz" },
        warn: { rate: "-4%", pitch: "-20Hz" },
        fail: { rate: "-8%", pitch: "-40Hz" },
        question: { rate: "+0%", pitch: "+15Hz" },

        dramatic:     { rate: "-15%", pitch: "-60Hz" },
        intimate:     { rate: "-5%",  pitch: "-25Hz" },
        intense:      { rate: "+5%",  pitch: "+20Hz" },
        ethereal:     { rate: "-20%", pitch: "+40Hz" },
        robotic:      { rate: "+10%", pitch: "-80Hz" },
        whispered:    { rate: "-25%", pitch: "-10Hz" },
        storyteller:  { rate: "-8%",  pitch: "-15Hz" },
        energetic:    { rate: "+15%", pitch: "+30Hz" },
      }.freeze

      DEFAULT_VOICE = Policy.single_voice_key
      DEFAULT_STYLE = :calm
      CHUNK_CHARS = 220

      extend SpeechWorker

      module_function

      def last_error = @last_error

      def clear_last_error! = (@last_error = nil)

      def available?
        edge_tts_available? || !espeak_path.nil? || Engines.replicate_token? || say_available?
      end

      def say_available?
        Engines.available?("say", {})
      end

      # Cheap and deliberately incomplete: the two preconditions a caller can
      # test without spawning anything. It gates the synthesis path, which runs
      # per utterance and must not pay for a subprocess, and where a wrong yes
      # costs one failed attempt and a fallback. Ask edge_tts_ready? where a
      # wrong yes is reported to somebody.
      def edge_tts_available?
        worker_executable? && eventmachine_ssl_available?
      end

      # The whole precondition set, asked of the worker instead of restated
      # here. bin/tts-worker also requires rb_edge_tts and faye/websocket, and
      # listing those in a second place is how the two drift — so --selftest
      # proves them by reaching its own exit. Memoised against the worker and
      # the lockfile, because the answer only changes when one of them does.
      def edge_tts_ready?
        edge_tts_blocker.nil?
      end

      # Why the worker could not speak, or nil. The reason is the point: a
      # health endpoint that says false without saying why sends its reader
      # back to re-derive it.
      def edge_tts_blocker
        @selftest_mutex.synchronize do
          stamp = selftest_stamp
          next @selftest_blocker if @selftest_stamp == stamp

          @selftest_stamp = stamp
          @selftest_blocker = probe_worker_selftest
        end
      end

      def worker_executable?
        File.executable?(WORKER)
      end

      # The lockfile is keyed by content, not mtime: bundler rewrites it when it
      # re-resolves, and a touch that changes nothing must not re-spawn the
      # probe it memoises. The worker script is keyed by mtime because nothing
      # writes to it.
      def selftest_stamp
        lock = File.join(Master::ROOT, "Gemfile.lock")
        [
          File.exist?(WORKER) ? File.mtime(WORKER).to_i : 0,
          File.exist?(lock) ? Digest::SHA256.file(lock).hexdigest : "",
        ]
      end

      def probe_worker_selftest
        return "worker is not executable at #{WORKER}" unless worker_executable?

        _out, err, status = Master::Io::Exec.capture3(
          TtsSupervisor.daemon_env(Master::ROOT), Gem.ruby, WORKER, "--selftest",
          chdir: Master::ROOT, timeout: SELFTEST_TIMEOUT_S
        )
        return if status.success?

        detail = err.to_s.lines.map(&:strip).reject(&:empty?).first
        "worker selftest exited #{status.exitstatus}#{": #{detail}" if detail}"
      rescue StandardError => e
        "worker selftest could not run: #{e.class}: #{e.message}"
      end

      def espeak_path
        ESPEAK_PATHS.find { |p| File.executable?(p) }
      end

      def eventmachine_ssl_available?
        require "eventmachine"
        return true unless EventMachine.respond_to?(:ssl?)

        EventMachine.ssl?
      rescue LoadError => e
        warn_tts("edge unavailable: eventmachine failed to load (#{e.message})")
        false
      rescue StandardError => e
        warn_tts("edge availability probe failed: #{e.class}: #{e.message}")
        false
      end

      # The voice for one utterance.
      #
      # MASTER_TTS_VOICE still wins outright: an operator naming a voice by hand is
      # asking for that voice, not for a lottery. Absent it, Policy decides — one
      # name while `rotation` holds fewer than two, a random pick from it otherwise.
      #
      # Per utterance rather than per process, so a long reply can change speaker
      # between sentences. That is the intent: two people narrating one piece of
      # work, rather than one person who occasionally sounds different.
      def default_voice
        named = ENV["MASTER_TTS_VOICE"].to_s.strip
        unless named.empty?
          sym = named.to_sym
          return VOICES.key?(sym) ? sym : DEFAULT_VOICE
        end

        chosen = Policy.voice_for_utterance
        VOICES.key?(chosen) ? chosen : DEFAULT_VOICE
      end

      def voice_for_text(text)
        named = ENV["MASTER_TTS_VOICE"].to_s.strip
        return default_voice unless named.empty?

        chosen = Policy.voice_for_text(text)
        VOICES.key?(chosen) ? chosen : DEFAULT_VOICE
      end

      def default_style
        ENV.fetch("MASTER_TTS_STYLE", DEFAULT_STYLE.to_s).to_sym.tap do |style|
          return STYLES.key?(style) ? style : DEFAULT_STYLE
        end
      end

      def style_config_for(_voice, style)
        STYLES.fetch(style.to_sym, STYLES[default_style]).dup
      end

      def infer_style(text, fallback: default_style)
        t = text.to_s.strip
        return fallback if t.empty?
        return :fail if t.match?(/\b(fail|failed|broken|blocked|error|abort)\b/i)
        return :warn if t.match?(/\b(warn|warning|careful|risk|unsafe)\b/i)
        return :question if t.end_with?("?")
        return :brief if t.split.size <= BRIEF_STYLE_WORD_COUNT
        fallback
      end

      # StrunkPass runs after newline->period conversion (preserves TTS pacing
      # for lines with no trailing punctuation) but before the final
      # whitespace collapse, stripping sycophancy/hedges/preambles/endings
      # (data/voice.yml voice.strunk) that the markdown-symbol gsubs below
      # never touched -- enforces master_output_format's "never use:
      # Certainly, Of course..." on the output side, which nothing did before.
      def clean_text(text)
        StrunkPass.call(
          text.to_s
            .gsub(/```.*?```/m, " code omitted. ")
            .gsub(/`([^`]+)`/, "\\1")
            .gsub(/https?:\/\/\S+/, " link omitted ")
            .gsub(/[•●▪▫◦]/, ". ")
            .gsub(/[\t\r\n]+/, ". ")
            .gsub(/[*_#>\[\]{}|]/, " "),
        )
          .gsub(/\.{3,}/, ".")
          .strip
          .then { |t| Lexicon.apply(t) }
      end

      def chunks(text, max: CHUNK_CHARS)
        clean = clean_text(text)
        return [] if clean.empty?

        sentences = clean.scan(/[^.!?]+[.!?]?/).map(&:strip).reject(&:empty?)
        out = []
        sentences.each do |sentence|
          if out.any? && (out[-1].length + sentence.length + 1) <= max
            out[-1] = "#{out[-1]} #{sentence}"
          elsif sentence.length > max
            out.concat(sentence.scan(/.{1,#{max}}(?:\s|\z)/).map(&:strip).reject(&:empty?))
          else
            out << sentence
          end
        end
        out.empty? ? [clean] : out
      end

      def synthesis_mode
        return ENV["MASTER_TTS_MODE"] if ENV.key?("MASTER_TTS_MODE")

        cfg = Transcendent.load_config
        if Engines.openbsd? && Transcendent.enabled?
          return "transcendent"
        end

        cfg["default_mode"].to_s == "transcendent" && Transcendent.enabled? ? "transcendent" : "classic"
      end

      def synthesize(text, voice: nil, style: default_style, rate: nil, pitch: nil, mode: nil, voice_locked: false, style_locked: false)
        text_str = clean_text(text)
        return if text_str.empty?

        voice ||= voice_for_text(text_str)
        attempted, result = try_transcendent_synthesis(
          text_str, mode, voice:, style:, rate:, pitch:, voice_locked:, style_locked:
        )
        return result if attempted && result

        return unless available?

        voice, style_config = resolve_voice_and_style(text_str, voice:, style:, rate:, pitch:, style_locked:)

        if edge_tts_available?
          path = synthesize_edge(text_str, voice:, style_config:)
          return path if path
        end

        path = synthesize_espeak(text_str) if espeak_path
        return path if path

        synthesize_say(text_str)
      end

      def try_transcendent_synthesis(text_str, mode, voice:, style:, rate:, pitch:, voice_locked:, style_locked:)
        use_mode = (mode || synthesis_mode).to_s
        return [false, nil] unless use_mode == "transcendent" && Transcendent.enabled?

        result = Transcendent.synthesize(
          text_str, voice:, style:, rate:, pitch:,
          voice_locked:, style_locked:
        )
        # Shaped here too. The chain was applied on the legacy Edge path only,
        # and synthesis_mode has been "transcendent" since Transcendent shipped,
        # so every reply this machine spoke went out bare: measured 2026-09-16,
        # a live utterance came back at -25.3 LUFS on the raw path and -17.2
        # through the chain. voice.yml declared it, Policy read it, Speech
        # applied it, and nothing on the live path ever called it.
        [true, shaped(result)]
      end

      def resolve_voice_and_style(text_str, voice:, style:, rate:, pitch:, style_locked:)
        style = infer_style(text_str, fallback: default_style) if style == :auto && !style_locked
        expr = Master::Voice::Expression.for_text(text_str)
        if expr[:register] == :creative && %i[neutral normal clear].include?(style) then style = expr[:style] end
        style = default_style unless STYLES.key?(style)
        voice = resolve_voice(voice)

        style_config = style_config_for(voice, style)
        style_config[:rate] = rate.to_s if rate && !rate.to_s.strip.empty?
        style_config[:pitch] = pitch.to_s if pitch && !pitch.to_s.strip.empty?

        [voice, style_config]
      end

      def synthesize_audio(text, **opts)
        path = synthesize(text, **opts)
        return unless path

        Audio.new(bytes: File.binread(path), mime_type: mime_type_for(path))
      ensure
        File.unlink(path) rescue nil if path
      end

      def resolve_voice(voice)
        key = voice.to_s.strip.to_sym
        return key if VOICES.key?(key)

        VOICES.find { |_sym, name| name == voice.to_s }&.first || default_voice
      end

      def synthesize_bytes(text, **opts)
        clear_last_error!
        TtsSupervisor.ensure_daemon!
        audio = synthesize_audio(text, **opts)
        bytes = audio&.bytes
        if bytes.nil? || bytes.empty?
          @last_error ||= "synthesis produced empty audio"
          return
        end
        bytes
      end

      # The web path, and Transcendent is not on it. Transcendent.synthesize returns a
      # finished file, while this path hands TtsJob progressive chunks through on_chunk
      # so audio starts before synthesis ends. Routing one through the other buffers the
      # whole utterance first, so the choice is progressive playback or
      # emotion/melody/multi-engine, not a missing call. Measure phrase fan-out (one
      # Edge round trip per phrase, on one vCPU) before making it.
      def synthesize_streaming_to_file(text, output_path:, on_chunk: nil, **opts)
        @synthesis_mutexes[next_synthesis_slot].synchronize do
          synthesize_streaming_to_file_unlocked(text, output_path:, on_chunk:, **opts)
        end
      end

      def next_synthesis_slot
        @synthesis_rr_mutex.synchronize do
          size = [TtsSupervisor.pool_size, 1].max
          slot = @synthesis_rr % size
          @synthesis_rr += 1
          slot
        end
      end

      def synthesize_streaming_to_file_unlocked(text, output_path:, on_chunk: nil, **opts)
        clear_last_error!
        text_str = clean_text(text)
        return false if text_str.empty?

        voice, style_config = resolve_streaming_style(text_str, opts)

        # The web path used to bypass Transcendent entirely, so the face got
        # one flat Edge utterance while the CLI already had emotion, phrase
        # rhythm and engine fallback. Use the same expressive path when enabled;
        # short lines or unavailable engines fall through to the proven Edge path.
        return true if transcendent_stream_written?(text_str, voice, opts, output_path, on_chunk)
        return true if edge_stream_written?(text_str, voice, style_config, output_path, on_chunk)

        # Edge TTS is a third-party network call (Microsoft) that can time out
        # or be unreachable independent of anything local; without this, a
        # single Edge hiccup meant no audio at all even though espeak-ng sits
        # right there. synthesize() (the non-streaming caller) already had
        # this fallback -- this path (the one TtsJob actually uses) didn't.
        return true if attempt_espeak_synthesis(text_str, output_path, on_chunk)

        @last_error ||= "streaming synthesis produced empty audio"
        false
      rescue StandardError => e
        @last_error = "#{e.class}: #{e.message}"
        false
      end

      def transcendent_stream_written?(text_str, voice, opts, output_path, on_chunk)
        return false unless transcendent_streaming_enabled?(opts)

        transcendent_path = synthesize_transcendent_stream(text_str, voice:, opts:)
        return false unless transcendent_path

        FileUtils.cp(transcendent_path, output_path)
        File.delete(transcendent_path) rescue nil
        on_chunk&.call(File.size(output_path))
        true
      end

      def edge_stream_written?(text_str, voice, style_config, output_path, on_chunk)
        return false unless edge_tts_available?

        TtsSupervisor.ensure_daemon!
        voice_name = VOICES.fetch(voice.to_sym, VOICES[default_voice])
        attempt_socket_synthesis(text_str, voice_name, style_config, output_path, on_chunk) ||
          attempt_oneshot_synthesis(text_str, voice_name, style_config, output_path, on_chunk)
      end

      def transcendent_streaming_enabled?(opts)
        return false if opts[:transcendent] == false
        return true if opts[:transcendent] == true

        require_relative "transcendent"
        Transcendent.enabled?
      rescue StandardError
        false
      end

      def synthesize_transcendent_stream(text_str, voice:, opts:)
        require_relative "transcendent"
        path = Transcendent.synthesize(
          text_str,
          voice:,
          style: opts.fetch(:style) { :auto },
          rate: opts[:rate],
          pitch: opts[:pitch],
          voice_locked: opts[:voice_locked] == true,
          style_locked: opts[:style_locked] == true,
        )
        return unless path && File.size?(path)

        path
      rescue StandardError => e
        warn_tts("transcendent web path skipped: #{e.class}: #{e.message}")
        nil
      end

      def resolve_streaming_style(text_str, opts)
        voice = resolve_voice(opts.fetch(:voice) { default_voice })
        style = opts.fetch(:style) { default_style }
        style = infer_style(text_str, fallback: default_style) if style == :auto && !opts[:style_locked]
        style = default_style unless STYLES.key?(style)
        style_config = style_config_for(voice, style)
        style_config[:rate] = opts[:rate].to_s if opts[:rate] && !opts[:rate].to_s.strip.empty?
        style_config[:pitch] = opts[:pitch].to_s if opts[:pitch] && !opts[:pitch].to_s.strip.empty?
        [voice, style_config]
      end

      def attempt_socket_synthesis(text_str, voice_name, style_config, output_path, on_chunk)
        2.times do |attempt|
          path = synthesize_edge_socket(
            text: text_str,
            voice_name:,
            style_config:,
            audio_path: output_path,
            on_chunk:,
          )
          return true if path && File.exist?(output_path) && File.size(output_path) > 0

          break unless attempt.zero?

          TtsSupervisor.ensure_daemon!
          sleep 0.15
        end
        false
      end

      def attempt_oneshot_synthesis(text_str, voice_name, style_config, output_path, on_chunk)
        path = synthesize_edge_oneshot(
          text: text_str,
          voice_name:,
          style_config:,
          audio_path: output_path,
        )
        return false unless path && File.exist?(output_path) && File.size(output_path) > 0

        on_chunk&.call(File.size(output_path))
        true
      end

      def attempt_espeak_synthesis(text_str, output_path, on_chunk)
        return false unless espeak_path

        wav_path = synthesize_espeak(text_str)
        return false unless wav_path

        # output_path is always the caller's fixed *.mp3 cache path (TtsJob),
        # so espeak's wav needs transcoding, not just a file move -- reuse the
        # same ffmpeg conversion the say/Kokoro engines already rely on.
        ok = Engines.convert_to_mp3(wav_path, output_path)
        unless ok && File.exist?(output_path) && File.size(output_path) > 0
          warn_tts("espeak fallback: mp3 conversion failed")
          File.unlink(wav_path) rescue nil
          return false
        end

        on_chunk&.call(File.size(output_path))
        true
      end

      def mime_type_for(path)
        File.extname(path.to_s).downcase == ".wav" ? "audio/wav" : "audio/mpeg"
      end

      def synthesize_edge(text, voice:, style_config:)
        audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
        voice_name = VOICES.fetch(voice.to_sym, VOICES[default_voice])

        2.times do |attempt|
          sock_path = synthesize_edge_socket(text:, voice_name:, style_config:, audio_path:)
          return shaped(sock_path) if sock_path
          break unless attempt.zero? && edge_tts_available?

          TtsSupervisor.ensure_daemon!
          sleep 0.15
        end

        shaped(synthesize_edge_oneshot(text:, voice_name:, style_config:, audio_path:))
      end

      # data/voice.yml tts.post_chain, applied.
      #
      # Edge returns a bare neural voice with no shaping of its own, so every
      # decision about how MASTER sounds past the choice of mouth lives in that
      # chain — and a chain nothing applies is a declaration with no reader, which
      # is this tree's most-recorded defect.
      #
      # The original file survives any failure: no ffmpeg, a bad filter, a zero-byte
      # result all return the unshaped path. A missing effect must cost the effect,
      # never the sentence.
      def shaped(path)
        chain = Policy.post_chain
        return path unless path && chain && File.size?(path)

        out = path.sub(/\.mp3\z/, "_shaped.mp3")
        _stdout, _stderr, status = Master::Io::Exec.capture3("ffmpeg", "-y", "-i", path, "-af", chain, out)
        return path unless status.success? && File.size?(out)

        File.unlink(path)
        out
      rescue StandardError => e
        warn_tts("post_chain skipped: #{e.class}: #{e.message.lines.first.to_s.strip}")
        path
      end

      # Every failure is kept in last_error; the terminal hears each kind once.
      # Offline, every reply fails the same way, and one line per reply is
      # fourteen lines of the same news.
      def warn_tts(message)
        @last_error = message
        @warned_tts ||= {}
        return if @warned_tts[message]

        @warned_tts[message] = true
        ::Kernel.warn("tts: #{message}")
      end
    end
  end
end
