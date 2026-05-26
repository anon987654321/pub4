# frozen_string_literal: true

require "securerandom"
require "fileutils"
require "open3"

module Master
  module Voice
  module Speech
    WORKER = File.expand_path("../../../bin/tts-worker", __dir__)
    EDGE_TTS = File.executable?(WORKER)
    ESPEAK = %w[/usr/bin/espeak /usr/local/bin/espeak].find { |p| File.executable?(p) }

    Audio = Struct.new(:bytes, :mime_type, keyword_init: true)

    VOICES = {
      osman: "ms-MY-OsmanNeural",
      yasmin: "ms-MY-YasminNeural",
      ryan: "en-GB-RyanNeural",
      finn: "nb-NO-FinnNeural",
      steffan: "en-US-SteffanNeural"
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
      question: { rate: "+0%", pitch: "+15Hz" }
    }.freeze

    DEFAULT_VOICE = :ryan
    DEFAULT_STYLE = :clear
    MAX_CHARS = 900
    CHUNK_CHARS = 220

    module_function

    def available?
      EDGE_TTS || !ESPEAK.nil?
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

    def infer_style(text, fallback: default_style)
      t = text.to_s.strip
      return fallback if t.empty?
      return :fail if t.match?(/\b(fail|failed|broken|blocked|error|abort)\b/i)
      return :warn if t.match?(/\b(warn|warning|careful|risk|unsafe)\b/i)
      return :question if t.end_with?("?")
      return :brief if t.split.size <= 12
      fallback
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

    def synthesize(text, voice: default_voice, style: default_style)
      text_str = clean_text(text)
      return if text_str.empty?
      return unless available?

      style = infer_style(text_str, fallback: default_style) if style == :auto
      style = default_style unless STYLES.key?(style)
      voice = default_voice unless VOICES.key?(voice)

      if EDGE_TTS
        path = synthesize_edge(text_str, voice: voice, style: style)
        return path if path
      end

      synthesize_espeak(text_str) if ESPEAK
    end

    def synthesize_audio(text, **opts)
      path = synthesize(text, **opts)
      return unless path

      Audio.new(bytes: File.binread(path), mime_type: mime_type_for(path))
    ensure
      File.unlink(path) rescue nil if path
    end

    def synthesize_bytes(text, **opts)
      synthesize_audio(text, **opts)&.bytes
    end

    def mime_type_for(path)
      File.extname(path.to_s).downcase == ".wav" ? "audio/wav" : "audio/mpeg"
    end

    def synthesize_edge(text, voice:, style:)
      audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
      voice_name = VOICES.fetch(voice.to_sym, VOICES[default_voice])
      style_config = STYLES.fetch(style.to_sym, STYLES[default_style])

      _out, _err, status = Open3.capture3(
        WORKER, voice_name, style_config[:rate], style_config[:pitch], audio_path,
        stdin_data: text.to_s
      )
      return unless status.success?

      (File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end

    def synthesize_espeak(text)
      audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
      ok = system(
        ESPEAK, "-s", "162", "-p", "42", "-a", "125",
        "-w", audio_path, text.to_s,
        out: File::NULL, err: File::NULL
      )
      (ok && File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end
  end
  end
end
