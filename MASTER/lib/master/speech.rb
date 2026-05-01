# frozen_string_literal: true

require "securerandom"
require "fileutils"

module Master
  # TTS via edge-tts (Microsoft Neural voices) with espeak fallback.
  # Default persona: dark_malay / ms-MY-OsmanNeural / deep style.
  module Speech
    EDGE_TTS = %w[/home/dev/.local/bin/edge-tts /usr/local/bin/edge-tts].find { |p| File.executable?(p) }
    ESPEAK   = %w[/usr/bin/espeak /usr/local/bin/espeak].find { |p| File.executable?(p) }

    VOICES = {
      osman:   "ms-MY-OsmanNeural",
      yasmin:  "en-MY-YasminNeural",
      ryan:    "en-GB-RyanNeural",
      finn:    "nb-NO-FinnNeural",
      steffan: "en-US-SteffanNeural"
    }.freeze

    STYLES = {
      deep:    { rate: "-35%", pitch: "-150Hz" },
      heavy:   { rate: "-30%", pitch: "-120Hz" },
      normal:  { rate: "+0%",  pitch: "+0Hz"   },
      slow:    { rate: "-20%", pitch: "-60Hz"  },
      natural: { rate: "+8%",  pitch: "+20Hz"  }
    }.freeze

    DEFAULT_VOICE = :osman
    DEFAULT_STYLE = :natural

    module_function

    def available?
      !EDGE_TTS.nil? || !ESPEAK.nil?
    end

    # Returns path to generated audio file, or nil on failure.
    def synthesize(text, voice: DEFAULT_VOICE, style: DEFAULT_STYLE)
      return nil if text.to_s.strip.empty?

      if EDGE_TTS
        synthesize_edge(text, voice: voice, style: style)
      elsif ESPEAK
        synthesize_espeak(text)
      end
    end

    # Returns raw mp3/wav bytes, or nil.
    def synthesize_bytes(text, **opts)
      path = synthesize(text, **opts)
      return nil unless path
      bytes = File.binread(path)
      begin
        File.unlink(path)
      rescue StandardError => e
        nil
      end
      bytes
    end


PULSE_SOCKET = "/tmp/pulse/native".freeze
PULSE_DAEMON = "/data/data/com.termux/files/usr/bin/pulseaudio".freeze
PAPLAY_CANDIDATES = %w[
  /data/data/com.termux/files/usr/bin/paplay
  /usr/bin/paplay
  /usr/local/bin/paplay
].freeze
FFMPEG_CANDIDATES = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].freeze
DIRECT_PLAYERS = %w[aucat mpv ffplay aplay].freeze

def play(audio_path)
  return false unless audio_path && File.exist?(audio_path)
  play_via_pulse(audio_path) || play_direct(audio_path)
end

    private

    module_function

    def synthesize_edge(text, voice:, style:)
      tmp = "/tmp/m_tts_#{SecureRandom.hex(8)}.mp3"
      voice_name = VOICES.fetch(voice.to_sym, VOICES[DEFAULT_VOICE])
      style_config = STYLES.fetch(style.to_sym, STYLES[DEFAULT_STYLE])

      ok = system(
        EDGE_TTS,
        "--voice", voice_name,
        "--rate=#{style_config[:rate]}",
        "--pitch=#{style_config[:pitch]}",
        "--text", text.to_s,
        "--write-media", tmp,
        out: File::NULL, err: File::NULL
      )

      (ok && File.exist?(tmp) && File.size(tmp) > 0) ? tmp : nil
    end

    def synthesize_espeak(text)
      tmp = "/tmp/m_tts_#{SecureRandom.hex(8)}.wav"
      ok  = system(
        ESPEAK, "-s", "140", "-p", "30", "-a", "150",
        "-w", tmp, text.to_s,
        out: File::NULL, err: File::NULL
      )
      (ok && File.exist?(tmp) && File.size(tmp) > 0) ? tmp : nil
    end
  end
end
