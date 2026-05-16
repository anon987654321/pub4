# frozen_string_literal: true

require "securerandom"
require "fileutils"
require "open3"

module Master
  module Voice
  module Speech
    WORKER   = File.expand_path("../../../exe/tts-worker", __dir__)
    EDGE_TTS = File.executable?(WORKER)
    ESPEAK   = %w[/usr/bin/espeak /usr/local/bin/espeak].find { |p| File.executable?(p) }

    VOICES = {
      osman:   "ms-MY-OsmanNeural",
      yasmin:  "ms-MY-YasminNeural",
      ryan:    "en-GB-RyanNeural",
      finn:    "nb-NO-FinnNeural",
      steffan: "en-US-SteffanNeural"
    }.freeze

    STYLES = {
      deep:     { rate: "-32%", pitch: "-180Hz" },
      heavy:    { rate: "-30%", pitch: "-120Hz" },
      normal:   { rate: "+0%",  pitch: "+0Hz"   },
      slow:     { rate: "-20%", pitch: "-60Hz"  },
      natural:  { rate: "+8%",  pitch: "+20Hz"  },
      # Clause-aware; all rebased darker so fluctuations stay in Osman's low register.
      question: { rate: "-8%",  pitch: "-90Hz"  },
      exclaim:  { rate: "+10%", pitch: "-60Hz"  },
      whisper:  { rate: "-18%", pitch: "-200Hz" },
      grave:    { rate: "-28%", pitch: "-220Hz" }
    }.freeze

    DEFAULT_VOICE = :osman
    DEFAULT_STYLE = :deep

    # Picks a style from text shape when caller passes :auto.
    # Dark base (deep) for statements; rises/drops per clause type.
    def infer_style(text, fallback: DEFAULT_STYLE)
      t = text.to_s.strip
      return fallback if t.empty?
      return :exclaim  if t.match?(/!{1,3}\s*$/) || t.match?(/\b[A-Z]{4,}\b/)
      return :question if t.end_with?("?")
      return :grave    if t.match?(/\.{3,}\s*$|\u2026\s*$/) ||
                         t.match?(/\b(sorry|i'?m sorry|condolences|grief|loss|failed|broken)\b/i) ||
                         (t.split.size <= 5 && t.end_with?("."))
      return :whisper  if (t.start_with?("(") && t.end_with?(")")) ||
                         t.match?(/\b(between us|quietly|note|aside)\b/i)
      return :heavy    if t.match?(/\b(critical|error|warning|abort|fail)\b/i)
      fallback
    end

    module_function

    def available?
      !EDGE_TTS.nil? || !ESPEAK.nil?
    end

    def synthesize(text, voice: DEFAULT_VOICE, style: DEFAULT_STYLE)
      text_str = text.to_s.strip
      return if text_str.empty?

      style = infer_style(text, fallback: DEFAULT_STYLE) if style == :auto
      style = DEFAULT_STYLE unless STYLES.key?(style)
      voice = DEFAULT_VOICE unless VOICES.key?(voice)

      if EDGE_TTS
        synthesize_edge(text, voice: voice, style: style)
      elsif ESPEAK
        synthesize_espeak(text)
      end
    end

    def synthesize_bytes(text, **opts)
      path = synthesize(text, **opts)
      return unless path
      begin
        File.binread(path)
      ensure
        File.unlink(path) rescue nil
      end
    end

    # Shells out to exe/tts-worker — Falcon's Async scheduler blocks Process.fork
    # ("Closing scheduler with blocked operations"), and EventMachine.run inside a
    # request fiber conflicts with Falcon's reactor. A subprocess sidesteps both.
    def synthesize_edge(text, voice:, style:)
      audio_path   = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
      voice_name   = VOICES.fetch(voice.to_sym, VOICES[DEFAULT_VOICE])
      style_config = STYLES.fetch(style.to_sym, STYLES[DEFAULT_STYLE])

      _out, _err, status = Open3.capture3(
        WORKER, voice_name, style_config[:rate], style_config[:pitch], audio_path,
        stdin_data: text.to_s
      )
      return unless status.success?

      (File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end

    def synthesize_espeak(text)
      audio_path = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
      ok         = system(
        ESPEAK, "-s", "140", "-p", "30", "-a", "150",
        "-w", audio_path, text.to_s,
        out: File::NULL, err: File::NULL
      )
      (ok && File.exist?(audio_path) && File.size(audio_path) > 0) ? audio_path : nil
    end
  end
  end
end
