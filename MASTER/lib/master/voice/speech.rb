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
      deep:    { rate: "-35%", pitch: "-150Hz" },
      heavy:   { rate: "-30%", pitch: "-120Hz" },
      normal:  { rate: "+0%",  pitch: "+0Hz"   },
      slow:    { rate: "-20%", pitch: "-60Hz"  },
      natural: { rate: "+8%",  pitch: "+20Hz"  },
      # Clause-aware variants — auto-applied by infer_style when caller passes :auto.
      question:{ rate: "-10%", pitch: "+40Hz"  }, # rising lift, slight slowdown
      exclaim: { rate: "+15%", pitch: "+60Hz"  }, # energetic, brighter
      whisper: { rate: "-15%", pitch: "-30Hz"  }, # quiet, intimate
      grave:   { rate: "-25%", pitch: "-80Hz"  }  # sober, weighty
    }.freeze

    DEFAULT_VOICE = :yasmin
    DEFAULT_STYLE = :natural

    # P4: pick a style from text shape when caller asks for :auto.
    # Heuristic — questions lift, exclamations brighten, ALL-CAPS shouts,
    # ellipses/short-final go grave. Fallback: caller's default.
    def infer_style(text, fallback: DEFAULT_STYLE)
      t = text.to_s.strip
      return fallback if t.empty?
      return :exclaim  if t.match?(/!{1,3}\s*$/) || t.match?(/\b[A-Z]{4,}\b/)
      return :question if t.end_with?("?")
      return :grave    if t.match?(/\.{3,}\s*$|\u2026\s*$/) || t.match?(/\b(sorry|i'?m sorry|condolences|grief|loss)\b/i)
      return :whisper  if t.start_with?("(") && t.end_with?(")")
      fallback
    end

    PULSE_SOCKET     = "/tmp/pulse/native".freeze
    PULSE_DAEMON     = "/data/data/com.termux/files/usr/bin/pulseaudio".freeze
    PAPLAY_CANDIDATES = %w[
      /data/data/com.termux/files/usr/bin/paplay
      /usr/bin/paplay
      /usr/local/bin/paplay
    ].freeze
    FFMPEG_CANDIDATES = %w[/usr/bin/ffmpeg /usr/local/bin/ffmpeg].freeze
    DIRECT_PLAYERS    = %w[aucat mpv ffplay aplay].freeze

    module_function

    def available?
      !EDGE_TTS.nil? || !ESPEAK.nil?
    end

    def synthesize(text, voice: DEFAULT_VOICE, style: DEFAULT_STYLE)
      return if text.to_s.strip.empty?

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
      bytes = File.binread(path)
      File.unlink(path) rescue StandardError => _e
      bytes
    end

    def play(audio_path)
      return false unless audio_path && File.exist?(audio_path)
      play_via_pulse(audio_path) || play_direct(audio_path)
    end

    private

    module_function

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
