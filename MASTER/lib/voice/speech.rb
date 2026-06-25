# frozen_string_literal: true

require "securerandom"
require "fileutils"
require "open3"
require "socket"
require "json"
require "timeout"

module Master
  module Voice
    module Speech
      WORKER = File.expand_path("../../bin/tts-worker", __dir__)
      EDGE_TTS = File.executable?(WORKER)
      TTS_SOCKET = File.expand_path("../../.master/tts.sock", __dir__)
      ESPEAK_PATHS = %w[/usr/bin/espeak /usr/local/bin/espeak].freeze
      ESPEAK = ESPEAK_PATHS.find { |p| File.executable?(p) }
      WORKER_TIMEOUT = 20
      @last_error = nil

      Audio = Struct.new(:bytes, :mime_type, keyword_init: true)

      VOICES = {
        :"ms-MY-OsmanNeural" => "ms-MY-OsmanNeural",
        :"en-GB-RyanNeural" => "en-GB-RyanNeural",
        :"nb-NO-FinnNeural" => "nb-NO-FinnNeural",
        :"en-US-AndrewNeural" => "en-US-AndrewNeural",
        :"en-US-GuyNeural" => "en-US-GuyNeural",
        :"en-AU-WilliamNeural" => "en-AU-WilliamNeural",
        :"en-US-ChristopherNeural" => "en-US-ChristopherNeural",
        :"en-US-EricNeural" => "en-US-EricNeural",
        :"nb-NO-PernilleNeural" => "nb-NO-PernilleNeural",
        :"en-US-DavisNeural" => "en-US-DavisNeural",
        :"en-SG-WayneNeural" => "en-SG-WayneNeural",
        :"en-NG-EzinneNeural" => "en-NG-EzinneNeural",
        :"en-US-JennyNeural" => "en-US-JennyNeural",
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
        jenny: "en-US-JennyNeural"
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

        # Creative vocal effects for Osman (and other voices)
        dramatic:     { rate: "-15%", pitch: "-60Hz" },   # lower, slower, intense
        intimate:     { rate: "-5%",  pitch: "-25Hz" },   # close, warm
        intense:      { rate: "+5%",  pitch: "+20Hz" },   # urgent, raised
        ethereal:     { rate: "-20%", pitch: "+40Hz" },   # high, slow, airy
        robotic:      { rate: "+10%", pitch: "-80Hz" },   # flat, mechanical
        whispered:    { rate: "-25%", pitch: "-10Hz" },   # very soft, breathy feel via extreme rate
        storyteller:  { rate: "-8%",  pitch: "-15Hz" },   # narrative, measured
        energetic:    { rate: "+15%", pitch: "+30Hz" }    # lively, higher
      }.freeze

      DEFAULT_VOICE = :osman
      DEFAULT_STYLE = :calm
      MAX_CHARS = 900
      CHUNK_CHARS = 220

      module_function

      def last_error = @last_error

      def clear_last_error! = (@last_error = nil)

      def available?
        edge_tts_available? || !espeak_path.nil?
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
        warn_tts("edge unavailable: eventmachine cannot be loaded (#{e.message})")
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

      def style_config_for(voice, style)
        STYLES.fetch(style.to_sym, STYLES[default_style]).dup
      end

      def infer_style(text, fallback: default_style)
        t = text.to_s.strip
        return fallback if t.empty?
        return :fail if t.match?(/\b(fail|failed|broken|blocked|error|abort)\b/i)
        return :warn if t.match?(/\b(warn|warning|careful|risk|unsafe)\b/i)
        return :question if t.end_with?("?")
        return :brief if t.split.size <= 12
        fallback
      end

      # register_for: creative vs factual bias from prompt_style_principles + voice leaks.
      # Delegates to Expression (single source for all runtime → TTS + face mapping).
      def register_for(text)
        Master::Voice::Expression.for_text(text)[:register]
      end

      def clean_text(text)
        text.to_s
            .gsub(/```.*?```/m, " code omitted. ")
            .gsub(/`([^`]+)`/, "\\1")
            .gsub(/https?:\/\/\S+/, " link omitted ")
            .gsub(/[•●▪▫◦]/, ". ")
            .gsub(/[\t\r\n]+/, ". ")
            .gsub(/[*_#>\[\]{}|]/, " ")
            .gsub(/\s+/, " ")
            .gsub(/\.{3,}/, ".")
            .strip[0, MAX_CHARS]
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
        cfg["default_mode"].to_s == "transcendent" && Transcendent.enabled? ? "transcendent" : "classic"
      end

      def synthesize(text, voice: default_voice, style: default_style, rate: nil, pitch: nil, mode: nil)
        text_str = clean_text(text)
        return if text_str.empty?

        use_mode = (mode || synthesis_mode).to_s
        if use_mode == "transcendent" && Transcendent.enabled?
          return Transcendent.synthesize(text_str, voice: voice, style: style, rate: rate, pitch: pitch)
        end

        return unless available?

        style = infer_style(text_str, fallback: default_style) if style == :auto
        expr = Master::Voice::Expression.for_text(text_str)
        if expr[:register] == :creative && %i[neutral normal clear].include?(style) then style = expr[:style] end
        style = default_style unless STYLES.key?(style)
        voice = resolve_voice(voice)

        style_config = style_config_for(voice, style)
        style_config[:rate] = rate.to_s if rate && !rate.to_s.strip.empty?
        style_config[:pitch] = pitch.to_s if pitch && !pitch.to_s.strip.empty?

        if edge_tts_available?
          path = synthesize_edge(text_str, voice: voice, style_config: style_config)
          return path if path
        end

        synthesize_espeak(text_str) if espeak_path
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
          return nil
        end
        bytes
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

        timeout = worker_timeout
        _out, err, status = Timeout.timeout(timeout) do
          Open3.capture3(
            WORKER, voice_name, style_config[:rate], style_config[:pitch], audio_path,
            stdin_data: text.to_s
          )
        end
        unless status.success?
          warn_tts("edge worker failed: #{err.to_s.strip}") unless err.to_s.strip.empty?
          return cleanup_failed_audio(audio_path)
        end

        return audio_path if File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("edge worker produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue Timeout::Error
        warn_tts("edge worker timed out after #{worker_timeout}s")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("edge worker error: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
      end

      def synthesize_edge_socket(text:, voice_name:, style_config:, audio_path:)
        return nil unless File.socket?(TTS_SOCKET)

        req = JSON.generate(
          voice: voice_name,
          rate: style_config[:rate],
          pitch: style_config[:pitch],
          text: text.to_s
        )
        Timeout.timeout(worker_timeout) do
          UNIXSocket.open(TTS_SOCKET) do |s|
            s.write("#{req}\n")
            File.open(audio_path, "wb") { |f| IO.copy_stream(s, f) }
          end
        end
        return audio_path if File.exist?(audio_path) && File.size(audio_path) > 0

        warn_tts("edge socket produced empty audio")
        cleanup_failed_audio(audio_path)
      rescue Timeout::Error
        warn_tts("edge socket timed out after #{worker_timeout}s")
        cleanup_failed_audio(audio_path)
      rescue StandardError => e
        warn_tts("edge socket failed: #{e.class}: #{e.message}")
        cleanup_failed_audio(audio_path)
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

      def worker_timeout
        Integer(ENV.fetch("MASTER_TTS_TIMEOUT", WORKER_TIMEOUT.to_s))
      rescue ArgumentError
        WORKER_TIMEOUT
      end

      def warn_tts(message)
        @last_error = message
        Kernel.warn("tts: #{message}")
      end
    end
  end
end
