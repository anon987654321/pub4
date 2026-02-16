# frozen_string_literal: true

module MASTER
  module Speech
    # Streaming - real-time audio streaming with FFmpeg effects
    module Streaming
      module_function

      # Stream with real-time FFmpeg effects (requires edge-tts + ffmpeg)
      def stream(text, effect: :dark, voice: :guy, rate: "-25%", pitch: "-25Hz")
        python = Utils.find_python
        return Result.err("Python not found.") unless python
        return Result.err("edge-tts not installed.") unless Utils.edge_installed?

        voice_id = EDGE_VOICES[voice.to_sym] || EDGE_VOICES[:guy]
        fx_filter = STREAM_EFFECTS[effect.to_sym] || STREAM_EFFECTS[:dark]

        ffmpeg = ENV["FFMPEG_PATH"] || "ffmpeg"
        ffplay = ENV["FFPLAY_PATH"] || "ffplay"

        tts_cmd = [python, "-m", "edge_tts",
                   "--text", text,
                   "--voice", voice_id,
                   "--rate=#{rate}",
                   "--pitch=#{pitch}",
                   "--write-media", "-"]

        null = RUBY_PLATFORM =~ /mingw|mswin|cygwin/ ? "NUL" : "/dev/null"

        tts = IO.popen(tts_cmd, "rb", err: null)
        fx = IO.popen([ffmpeg, "-i", "pipe:0", "-af", fx_filter, "-f", "wav", "pipe:1"], "r+b", err: null)
        play = IO.popen([ffplay, "-nodisp", "-autoexit", "-i", "pipe:0"], "wb", err: null)

        Thread.new { IO.copy_stream(tts, fx); fx.close_write }
        IO.copy_stream(fx, play)

        [tts, fx, play].each(&:close)
        Result.ok(text: text, effect: effect)
      rescue StandardError => e
        Result.err("Stream failed: #{e.message}")
      end

      # Demon mode (maximum darkness effect)
      def demon(text)
        stream(text, effect: :demon, rate: "-35%", pitch: "-35Hz")
      end

      # Continuous chatter mode (for Windows background talking)
      def chatter(topic: :master, effect: :calm, delay: 2.0)
        topics = {
          master: [
            "Consider adding a visual diff preview before applying changes.",
            "What if MASTER could learn from rejected suggestions?",
            "The axiom enforcement could have graduated severity levels.",
            "A cost projection before expensive operations would build trust.",
            "Self-test on boot ensures integrity after updates.",
          ],
          code: [
            "Extract that repeated pattern into a shared helper.",
            "This function does two things. Consider splitting it.",
            "Add a timeout to that external call.",
            "The magic number should be a named constant.",
          ],
          philosophy: [
            "Simplicity is the ultimate sophistication.",
            "Make it work, make it right, make it fast.",
            "The best code is no code at all.",
          ],
        }

        suggestions = topics[topic.to_sym] || topics[:master]
        loop do
          stream(suggestions.sample, effect: effect)
          sleep delay
        end
      end
    end
  end
end
