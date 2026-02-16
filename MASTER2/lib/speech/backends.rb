# frozen_string_literal: true

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
        escaped = text.gsub('"', '\\"').gsub("`", "\\`")

        cmd = if RUBY_PLATFORM =~ /mingw|mswin|cygwin/
                "echo #{escaped} | py -m piper --model #{model} --output #{output} --length_scale #{params[:length_scale]} --noise_scale #{params[:noise_scale]}"
              else
                "echo \"#{escaped}\" | piper --model #{model} --output_file #{output} --length_scale #{params[:length_scale]} --noise_scale #{params[:noise_scale]} 2>/dev/null"
              end

        success = system(cmd)
        return Result.err("Piper generation failed.") unless success && File.exist?(output)

        Playback.play_audio(output) if play
        FileUtils.rm_f(output) if play

        Result.ok(engine: :piper, voice: voice, preset: preset)
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

        Playback.play_audio(output) if play
        FileUtils.rm_f(output) if play

        Result.ok(engine: :edge, voice: voice_id, style: style)
      end

      # Replicate TTS (paid cloud)
      def speak_replicate(text, play: true)
        require "net/http"
        require "json"

        token = ENV["REPLICATE_API_TOKEN"]
        return Result.err("No REPLICATE_API_TOKEN.") unless token

        uri = URI("https://api.replicate.com/v1/models/minimax/speech-02-turbo/predictions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{token}"
        request["Content-Type"] = "application/json"
        request["Prefer"] = "wait"
        request.body = { input: { text: text, voice_id: "Casual_Guy" } }.to_json

        response = http.request(request)
        data = JSON.parse(response.body, symbolize_names: true)

        audio_url = data[:output]
        return Result.err("No audio URL returned.") unless audio_url

        if play
          temp = File.join(Dir.tmpdir, "replicate_#{SecureRandom.hex(4)}.wav")
          Playback.download_and_play(audio_url, temp)
        end

        Result.ok(engine: :replicate, url: audio_url)
      rescue StandardError => e
        Result.err("Replicate error: #{e.message}")
      end
    end
  end
end
