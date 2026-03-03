# frozen_string_literal: true

module MASTER
  module Speech
    # Streaming - real-time audio streaming with FFmpeg effects
    module Streaming
      module_function

      # Stream with real-time FFmpeg effects (requires edge-tts CLI + ffmpeg + ffplay)
      def stream(text, effect: :demon, voice: :osman, rate: "-35%", pitch: "-150Hz")
        cmd = Utils.find_edge_tts
        return Result.err("edge-tts not found. Install: pipx install edge-tts") unless cmd

        voice_id  = EDGE_VOICES[voice.to_sym] || EDGE_VOICES[:osman]
        fx_filter = STREAM_EFFECTS[effect.to_sym] || STREAM_EFFECTS[:dark]

        ffmpeg = ENV["FFMPEG_PATH"] || "ffmpeg"
        ffplay = ENV["FFPLAY_PATH"] || "ffplay"

        tts_cmd = [cmd,
                   "--voice", voice_id,
                   "--rate=#{rate}",
                   "--pitch=#{pitch}",
                   "--text", text,
                   "--write-media", "-"]

        null = File::NULL

        tts  = IO.popen(tts_cmd, "rb", err: null)
        fx   = IO.popen([ffmpeg, "-i", "pipe:0", "-af", fx_filter, "-f", "wav", "pipe:1"], "r+b", err: null)
        play = IO.popen([ffplay, "-nodisp", "-autoexit", "-i", "pipe:0"], "wb", err: null)

        Thread.new do
          IO.copy_stream(tts, fx)
          fx.close_write
        end
        IO.copy_stream(fx, play)

        [tts, fx, play].each(&:close)
        Result.ok(text: text, effect: effect)
      rescue StandardError => err
        Result.err("Stream failed: #{err.message}")
      end

      # Demon mode (maximum darkness)
      def demon(text)
        stream(text, effect: :demon, voice: :osman, rate: "-40%", pitch: "-200Hz")
      end

      # Continuous chatter mode
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
