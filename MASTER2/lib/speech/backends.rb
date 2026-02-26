# frozen_string_literal: true

require "open3"

module MASTER
  module Speech
    # Backends - TTS engine implementations (Piper, Edge, Replicate)
    module Backends
      module_function

      # Piper TTS (local)
      def speak_piper(text, voice: nil, preset: :normal, play: true)
        voice ||= "en_US-lessac-medium"
        params = PIPER_PRESETS[preset.to_sym] || PIPER_PRESETS[:normal]

        voices_dir = File.join(Paths.var, "piper_voices")
        FileUtils.mkdir_p(voices_dir)
        model = File.join(voices_dir, "#{voice}.onnx")

        output = File.join(Dir.tmpdir, "piper_#{SecureRandom.hex(4)}.wav")

        # Use Open3 with array form: text piped via stdin, no shell injection risk
        piper_cmd = ["piper", "--model", model,
                     "--output_file", output,
                     "--length_scale", params[:length_scale].to_s,
                     "--noise_scale", params[:noise_scale].to_s]
        _out, _err, status = Open3.capture3(*piper_cmd, stdin_data: text)
        success = status.success?
        return Result.err("Piper generation failed.") unless success && File.exist?(output)

        audio = File.binread(output)
        Playback.play_audio(output) if play
        FileUtils.rm_f(output)

        Result.ok(engine: :piper, voice: voice, preset: preset, audio: audio, content_type: "audio/wav")
      end

      # Edge TTS (free cloud)
      def speak_edge(text, voice: nil, style: :normal, play: true)
        python = Utils.find_python
        return Result.err("Python not found.") unless python

        voice_id = EDGE_VOICES[voice&.to_sym] || EDGE_VOICES[:aria]
        params = STYLES[style.to_sym] || STYLES[:normal]

        output_dir = Paths.edge_tts_output
        FileUtils.mkdir_p(output_dir)
        output = File.join(output_dir, "edge_#{SecureRandom.hex(4)}.mp3")

        script = <<~PY
          import asyncio
          import edge_tts
          async def main():
              communicate = edge_tts.Communicate(
                  #{text.inspect},
                  voice="#{voice_id}",
                  rate="#{params[:rate]}",
                  pitch="#{params[:pitch]}"
              )
              await communicate.save("#{output.gsub('\\', '/')}")
          asyncio.run(main())
        PY

        success = system("#{python} -c #{script.inspect} 2>/dev/null")
        return Result.err("Edge TTS generation failed.") unless success && File.exist?(output)

        audio = File.binread(output)
        Playback.play_audio(output) if play
        FileUtils.rm_f(output)

        Result.ok(engine: :edge, voice: voice_id, style: style, audio: audio, content_type: "audio/mpeg")
      end

      # Replicate TTS (paid cloud) -- uses Replicate::Client (async-http)
      def speak_replicate(text, play: true)
        token = ENV.fetch("REPLICATE_API_TOKEN", nil)
        return Result.err("No REPLICATE_API_TOKEN.") unless token

        result = Replicate::Client.create_prediction(
          model: "minimax/speech-02-turbo",
          input: { text: text, voice_id: "Casual_Guy" },
        )
        return Result.err("Replicate error: #{result[:error]}") if result[:error]

        # Speech predictions complete synchronously with Prefer: wait --
        # poll until done to retrieve the audio URL.
        poll = Replicate::Client.wait_for_completion(result[:id])
        return Result.err("Replicate poll error: #{poll[:error]}") if poll[:error]

        audio_url = poll[:output]
        return Result.err("No audio URL returned.") unless audio_url

        if play
          temp = File.join(Dir.tmpdir, "replicate_#{SecureRandom.hex(4)}.wav")
          Playback.download_and_play(audio_url, temp)
        end

        Result.ok(engine: :replicate, url: audio_url)
      rescue StandardError => err
        Result.err("Replicate error: #{err.message}")
      end
    end
  end
end
