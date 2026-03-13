# frozen_string_literal: true

require "securerandom"
require "fileutils"

module Master
  # TTS via edge-tts (Microsoft Neural voices).
  # Default persona: dark_malay / ms-MY-OsmanNeural / deep style.
  module Speech
    EDGE_TTS = "/home/dev/.local/bin/edge-tts"

    VOICES = {
      osman:   "ms-MY-OsmanNeural",
      yasmin:  "en-MY-YasminNeural",
      ryan:    "en-GB-RyanNeural",
      finn:    "nb-NO-FinnNeural",
      steffan: "en-US-SteffanNeural"
    }.freeze

    STYLES = {
      deep:   { rate: "-35%", pitch: "-150Hz" },
      heavy:  { rate: "-30%", pitch: "-120Hz" },
      normal: { rate: "+0%",  pitch: "+0Hz"   },
      slow:   { rate: "-20%", pitch: "-60Hz"  }
    }.freeze

    DEFAULT_VOICE = :osman
    DEFAULT_STYLE = :deep

    module_function

    def available?
      File.executable?(EDGE_TTS)
    end

    # Returns path to generated mp3, or nil on failure.
    def synthesize(text, voice: DEFAULT_VOICE, style: DEFAULT_STYLE)
      return nil unless available?
      return nil if text.to_s.strip.empty?

      tmp = "/tmp/m3_tts_#{SecureRandom.hex(8)}.mp3"
      v   = VOICES.fetch(voice.to_sym, VOICES[DEFAULT_VOICE])
      s   = STYLES.fetch(style.to_sym,  STYLES[DEFAULT_STYLE])

      ok = system(
        EDGE_TTS,
        "--voice", v,
        "--rate=#{s[:rate]}",
        "--pitch=#{s[:pitch]}",
        "--text", text.to_s,
        "--write-media", tmp,
        out: File::NULL, err: File::NULL
      )

      (ok && File.exist?(tmp) && File.size(tmp) > 0) ? tmp : nil
    end

    # Returns raw mp3 bytes, or nil.
    def synthesize_bytes(text, **opts)
      path = synthesize(text, **opts)
      return nil unless path
      bytes = File.binread(path)
      File.unlink(path) rescue nil
      bytes
    end
  end
end
