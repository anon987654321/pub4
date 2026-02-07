# frozen_string_literal: true

module MASTER
  # StreamTTS: Real-time TTS streaming with live audio effects
  # Uses IO.popen for elegant Unix-style pipe handling
  module StreamTTS
    extend self

    VOICE = "en-US-GuyNeural"
    RATE_DARK = "-25%"
    PITCH_DARK = "-25Hz"
    RATE_DEMON = "-35%"
    PITCH_DEMON = "-35Hz"

    FFMPEG = ENV["FFMPEG_PATH"] || "ffmpeg"
    FFPLAY = ENV["FFPLAY_PATH"] || "ffplay"

    # Effect presets
    EFFECTS = {
      dark: "asetrate=44100*0.8,atempo=1.25,bass=g=10",
      demon: "asetrate=44100*0.7,atempo=1.4,bass=g=15,acompressor=threshold=0.08:ratio=12",
      robot: "asetrate=44100*0.9,atempo=1.1,flanger,tremolo=f=10:d=0.5",
      radio: "highpass=f=300,lowpass=f=3000,acompressor=threshold=0.1:ratio=8",
      underwater: "asetrate=44100*0.6,atempo=1.6,lowpass=f=800,chorus=0.5:0.9:50:0.4:0.25:2",
      ghost: "asetrate=44100*0.75,atempo=1.33,areverse,aecho=0.8:0.88:60:0.4,areverse",
    }.freeze

    # Stream TTS directly to speakers with effects
    def stream(text, effect: :dark, voice: VOICE, rate: RATE_DARK, pitch: PITCH_DARK)
      python = find_python
      return unless python

      tts_cmd = [python, "-m", "edge_tts",
                 "--text", text,
                 "--voice", voice,
                 "--rate=#{rate}",
                 "--pitch=#{pitch}",
                 "--write-media", "-"]

      fx_filter = EFFECTS[effect] || EFFECTS[:dark]

      tts = IO.popen(tts_cmd, "rb", err: null_device)
      fx = IO.popen([FFMPEG, "-i", "pipe:0", "-af", fx_filter, "-f", "wav", "pipe:1"],
                    "r+b", err: null_device)
      play = IO.popen([FFPLAY, "-nodisp", "-autoexit", "-i", "pipe:0"],
                      "wb", err: null_device)

      Thread.new { IO.copy_stream(tts, fx); fx.close_write }
      IO.copy_stream(fx, play)

      [tts, fx, play].each(&:close)
    rescue StandardError => e
      warn "StreamTTS error: #{e.message}"
    end

    # Stream without effects (raw TTS)
    def stream_raw(text, voice: VOICE, rate: RATE_DARK, pitch: PITCH_DARK)
      python = find_python
      return unless python

      tts_cmd = [python, "-m", "edge_tts",
                 "--text", text,
                 "--voice", voice,
                 "--rate=#{rate}",
                 "--pitch=#{pitch}",
                 "--write-media", "-"]

      tts = IO.popen(tts_cmd, "rb", err: null_device)
      play = IO.popen([FFPLAY, "-nodisp", "-autoexit", "-i", "pipe:0"],
                      "wb", err: null_device)

      IO.copy_stream(tts, play)
      [tts, play].each(&:close)
    rescue StandardError => e
      warn "StreamTTS error: #{e.message}"
    end

    # Demon mode: maximum darkness
    def demon(text)
      stream(text, effect: :demon, rate: RATE_DEMON, pitch: PITCH_DEMON)
    end

    # Continuous loop: never stops talking
    def loop_forever(texts, effect: :dark, delay: 0.5)
      texts = [texts] if texts.is_a?(String)
      loop do
        stream(texts.sample, effect: effect)
        sleep delay
      end
    end

    # Windows constant talking - ideas and suggestions
    def windows_chatter(topic: :master)
      topics = {
        master: [
          "Consider adding a visual diff preview before applying changes.",
          "What if MASTER could learn from rejected suggestions?",
          "The axiom enforcement could have graduated severity levels.",
          "Session replay could help debug unexpected behavior.",
          "A cost projection before expensive operations would build trust.",
          "The pipeline stages could emit progress events for UI.",
          "Self-test on boot ensures integrity after updates.",
          "Graceful degradation chains prevent total failure.",
        ],
        code: [
          "Extract that repeated pattern into a shared helper.",
          "This function does two things. Consider splitting it.",
          "The variable name could be more descriptive.",
          "Add a timeout to that external call.",
          "Consider the error case here. What if it fails?",
          "This nesting is deep. Flatten with early returns.",
          "The magic number should be a named constant.",
        ],
        philosophy: [
          "Simplicity is the ultimate sophistication.",
          "Make it work, make it right, make it fast.",
          "The best code is no code at all.",
          "Every abstraction has a cost. Is this one worth it?",
          "Premature optimization is the root of all evil.",
          "Code is read more often than written.",
        ],
      }

      suggestions = topics[topic] || topics[:master]
      loop_forever(suggestions, effect: :calm, delay: 2.0)
    end

    # Adversarial loop: challenging questions
    def adversarial_loop(iterations: 5)
      challenges = [
        "Why are you still using external processes when Ruby can do it all?",
        "Have you considered that your entire approach might be wrong?",
        "What if everything you know about shell scripting is outdated?",
        "Are you afraid to push the boundaries of what code can be?",
        "Why do you accept mediocrity when excellence is within reach?",
        "When was the last time you deleted code instead of adding more?",
        "Is your code beautiful or just functional?",
      ]

      commands = %w[FIX\ IT DO\ BETTER TRY\ AGAIN PROVE\ IT DELETE\ IT REWRITE\ IT]

      iterations.times do |i|
        text = "#{challenges.sample}... #{commands.sample}... Iteration #{i + 1}."
        demon(text)
        sleep 0.3
      end
    end

    private

    def find_python
      %w[py python3 python].find { |p| system("#{p} --version > #{null_device} 2>&1") }
    end

    def null_device
      RUBY_PLATFORM =~ /mingw|mswin|cygwin/ ? "NUL" : "/dev/null"
    end
  end
end
