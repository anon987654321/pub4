# frozen_string_literal: true

require "securerandom"
require "fileutils"
require "open3"
require "socket"
require "json"
require "timeout"
require_relative "policy"
require_relative "strunk_pass"
require_relative "lexicon"

module Master
  module Voice
    module Speech
      WORKER = File.expand_path("../../bin/tts-worker", __dir__)
      EDGE_TTS = File.executable?(WORKER)
      BRIEF_STYLE_WORD_COUNT = 12
      TTS_SOCKET = File.expand_path("../../.master/tts.sock", __dir__)
      ESPEAK_PATHS = %w[/usr/bin/espeak /usr/local/bin/espeak].freeze
      ESPEAK = ESPEAK_PATHS.find { |p| File.executable?(p) }
      WORKER_TIMEOUT = 45
      # b2cc32b73 tuned WORKER_TIMEOUT for MAX_CHARS=900 on the VPS;
      # MAX_CHARS was later raised 4x (035888e8e) without touching the
      # timeout, so a full-length reply's single unchunked Edge TTS call
      # blew the fixed budget every time -- long replies produced no audio
      # at all. Scale the budget with text length instead of a flat cap.
      WORKER_TIMEOUT_PER_CHAR = 0.05
      WORKER_TIMEOUT_MAX = 180
      @last_error = nil
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

      VOICES = {
        "ms-MY-OsmanNeural": "ms-MY-OsmanNeural",
        "en-GB-RyanNeural": "en-GB-RyanNeural",
        "nb-NO-FinnNeural": "nb-NO-FinnNeural",
        "en-US-AndrewNeural": "en-US-AndrewNeural",
        "en-US-GuyNeural": "en-US-GuyNeural",
        "en-AU-WilliamNeural": "en-AU-WilliamNeural",
        "en-US-ChristopherNeural": "en-US-ChristopherNeural",
        "en-US-EricNeural": "en-US-EricNeural",
        "nb-NO-PernilleNeural": "nb-NO-PernilleNeural",
        "en-US-DavisNeural": "en-US-DavisNeural",
        "en-SG-WayneNeural": "en-SG-WayneNeural",
        "en-NG-EzinneNeural": "en-NG-EzinneNeural",
        "en-US-JennyNeural": "en-US-JennyNeural",
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
      }.freeze

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
      # generous MAX; historical truncation lost tail of replies; queue bounds cost
      MAX_CHARS = 4000
      CHUNK_CHARS = 220

      module_function

      def last_error = @last_error

      def clear_last_error! = (@last_error = nil)

      def available?
        edge_tts_available? || !espeak_path.nil? || Engines.replicate_token?
      end

      def edge_tts_available?
        worker_executable? && eventmachine_ssl_available?
      end

      def worker_executable?
        File.executable?(WORKER)
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

      def default_voice
        ENV.fetch("MASTER_TTS_VOICE", DEFAULT_VOICE.to_s).to_sym.tap do |voice|
          return VOICES.key?(voice) ? voice : DEFAULT_VOICE
        end
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

      def register_for(text)
        Master::Voice::Expression.for_text(text)[:register]
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
          .then { |t| Lexicon.apply(t) }[0, MAX_CHARS]
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

      def synthesize(text, voice: default_voice, style: default_style, rate: nil, pitch: nil, mode: nil, voice_locked: false, style_locked: false)
        text_str = clean_text(text)
        return if text_str.empty?

        attempted, result = try_transcendent_synthesis(
          text_str, mode, voice:, style:, rate:, pitch:, voice_locked:, style_locked:
        )
        return result if attempted

        return unless available?

        voice, style_config = resolve_voice_and_style(text_str, voice:, style:, rate:, pitch:, style_locked:)

        if edge_tts_available?
          path = synthesize_edge(text_str, voice:, style_config:)
          return path if path
        end

        synthesize_espeak(text_str) if espeak_path
      end

      def try_transcendent_synthesis(text_str, mode, voice:, style:, rate:, pitch:, voice_locked:, style_locked:)
        use_mode = (mode || synthesis_mode).to_s
        return [false, nil] unless use_mode == "transcendent" && Transcendent.enabled?

        result = Transcendent.synthesize(
          text_str, voice:, style:, rate:, pitch:,
          voice_locked:, style_locked:
        )
        [true, result]
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

        if edge_tts_available?
          TtsSupervisor.ensure_daemon!
          voice_name = VOICES.fetch(voice.to_sym, VOICES[default_voice])
          return true if attempt_socket_synthesis(text_str, voice_name, style_config, output_path, on_chunk)
          return true if attempt_oneshot_synthesis(text_str, voice_name, style_config, output_path, on_chunk)
        end

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
          return sock_path if sock_path
          break unless attempt.zero? && edge_tts_available?

          TtsSupervisor.ensure_daemon!
          sleep 0.15
        end

        synthesize_edge_oneshot(text:, voice_name:, style_config:, audio_path:)
      end

      def synthesize_edge_oneshot(text:, voice_name:, style_config:, audio_path:)
        timeout = worker_timeout(text.to_s.length)
        err, status = run_edge_worker(text, voice_name, style_config, audio_path, timeout)
        unless status.success?
          warn_tts("edge worker failed: #{err.to_s.strip}") unless err.to_s.strip.empty?
          return cleanup_failed_audio(audio_path)
        end

        return audio_path if File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("edge worker produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue Timeout::Error
        warn_tts("edge worker timed out after #{timeout}s")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("edge worker error: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      def run_edge_worker(text, voice_name, style_config, audio_path, timeout)
        # Delegate the timeout to Exec.capture3, which spawns in its own process
        # group and TERM/KILLs it on expiry. A previous outer Timeout.timeout
        # here fired first and bypassed that kill, orphaning a hung tts-worker
        # (and a retry then spawned a duplicate on the same output file).
        _out, err, status = Master::Io::Exec.capture3(
          TtsSupervisor.daemon_env(Master::ROOT),
          Gem.ruby, WORKER, voice_name, style_config[:rate], style_config[:pitch], audio_path,
          stdin_data: text.to_s,
          chdir: Master::ROOT,
          timeout:
        )
        [err, status]
      end

      def synthesize_edge_socket(text:, voice_name:, style_config:, audio_path:, on_chunk: nil)
        sock_path = resolve_socket_path
        return unless sock_path

        req = build_socket_request(voice_name, style_config, text)
        timeout = worker_timeout(text.to_s.length)
        stream_socket_response(sock_path, req, audio_path, timeout, on_chunk)
        return audio_path if File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("edge socket produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue Timeout::Error
        warn_tts("edge socket timed out after #{timeout}s")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("edge socket failed: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      def build_socket_request(voice_name, style_config, text)
        JSON.generate(
          voice: voice_name,
          rate: style_config[:rate],
          pitch: style_config[:pitch],
          text: text.to_s,
        )
      end

      def resolve_socket_path
        sock_path = TtsSupervisor.next_socket
        unless File.socket?(sock_path)
          TtsSupervisor.ensure_daemon!
          sock_path = TtsSupervisor.next_socket
        end
        File.socket?(sock_path) ? sock_path : nil
      end

      def stream_socket_response(sock_path, req, audio_path, timeout, on_chunk)
        Timeout.timeout(timeout) do
          UNIXSocket.open(sock_path) do |s|
            s.write("#{req}\n")
            File.open(audio_path, "wb") do |f|
              loop do
                begin
                  chunk = s.readpartial(8192)
                rescue EOFError
                  break
                end
                f.write(chunk)
                on_chunk&.call(f.pos)
              end
            end
          end
        end
      end

      def synthesize_espeak(text)
        audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
        ok = system(
          espeak_path, "-s", "162", "-p", "42", "-a", "125",
          "-w", audio_path, text.to_s,
          out: File::NULL, err: File::NULL
        )
        return audio_path if ok && File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("espeak failed or produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("espeak error: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      def cleanup_failed_audio(path)
        File.unlink(path) rescue nil if path
        nil
      end

      def worker_timeout(text_length = 0)
        return Integer(ENV.fetch("MASTER_TTS_TIMEOUT")) if ENV.key?("MASTER_TTS_TIMEOUT")

        [WORKER_TIMEOUT + (text_length * WORKER_TIMEOUT_PER_CHAR).ceil, WORKER_TIMEOUT_MAX].min
      rescue ArgumentError
        WORKER_TIMEOUT
      end

      def warn_tts(message)
        @last_error = message
        ::Kernel.warn("tts: #{message}")
      end
    end
  end
end
