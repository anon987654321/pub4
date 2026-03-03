# frozen_string_literal: true

require "open3"

module MASTER
  module Speech
    # Backends - TTS engine implementations (Piper, Edge CLI, espeak-ng, Replicate)
    module Backends
      module_function

      # Piper TTS (local, high-quality neural TTS)
      def speak_piper(text, voice: nil, preset: :normal, play: true)
        voice_file = PIPER_VOICES[voice&.to_sym] || PIPER_VOICES[:lessac]
        params = PIPER_PRESETS[preset.to_sym] || PIPER_PRESETS[:normal]

        voices_dir = File.join(Paths.var, "piper_voices")
        FileUtils.mkdir_p(voices_dir)
        model = File.join(voices_dir, "#{voice_file}.onnx")

        output = File.join(Dir.tmpdir, "piper_#{SecureRandom.hex(4)}.wav")

        piper_cmd = ["piper", "--model", model,
                     "--output_file", output,
                     "--length_scale", params[:length_scale].to_s,
                     "--noise_scale", params[:noise_scale].to_s]
        _out, _err, status = Open3.capture3(*piper_cmd, stdin_data: text)
        return Result.err("Piper generation failed.") unless status.success? && File.exist?(output)

        audio = File.binread(output)
        Playback.play_audio(output) if play
        FileUtils.rm_f(output)

        Result.ok(engine: :piper, voice: voice_file, preset: preset, audio: audio, content_type: "audio/wav")
      end

      # Edge TTS via CLI binary (no Python dependency at call time)
      # Install once: pip install edge-tts  OR  pipx install edge-tts
      # effect: FFmpeg filter applied after synthesis to bake in dark character server-side.
      # Defaults to :demon — guarantees the voice sounds deep/dark regardless of browser FX.
      def speak_edge(text, voice: nil, style: :normal, effect: :demon, play: true)
        cmd = Utils.find_edge_tts
        return Result.err("edge-tts not found. Install: pipx install edge-tts") unless cmd

        voice_id = EDGE_VOICES[voice&.to_sym] || EDGE_VOICES[:osman]
        params   = STYLES[style.to_sym] || STYLES[:normal]

        output_dir = Paths.edge_tts_output
        FileUtils.mkdir_p(output_dir)
        output = File.join(output_dir, "edge_#{SecureRandom.hex(4)}.mp3")

        tts_cmd = [cmd,
                   "--voice", voice_id,
                   "--rate",  params[:rate],
                   "--pitch", params[:pitch],
                   "--text",  text,
                   "--write-media", output]

        _out, err, status = Open3.capture3(*tts_cmd)
        return Result.err("Edge TTS failed: #{err.strip}") unless status.success? && File.exist?(output)

        # Bake FFmpeg effect into the audio server-side so browser always gets dark voice
        if effect && (fx_filter = STREAM_EFFECTS[effect.to_sym])
          ffmpeg = ENV.fetch("FFMPEG_PATH", "ffmpeg")
          processed = File.join(output_dir, "edge_fx_#{SecureRandom.hex(4)}.mp3")
          cmd = if fx_filter.start_with?("fc:")
            [ffmpeg, "-y", "-i", output, "-filter_complex", fx_filter[3..], "-map", "[out]", processed]
          else
            [ffmpeg, "-y", "-i", output, "-af", fx_filter, processed]
          end
          _fo, _fe, fst = Open3.capture3(*cmd)
          if fst.success? && File.exist?(processed)
            FileUtils.rm_f(output)
            output = processed
          end
          # FFmpeg failure is non-fatal — raw audio still has rate/pitch from synthesis
        end

        audio = File.binread(output)
        Playback.play_audio(output) if play
        FileUtils.rm_f(output)

        Result.ok(engine: :edge, voice: voice_id, style: style, effect: effect, audio: audio, content_type: "audio/mpeg")
      end

      # espeak-ng TTS (local fallback, robotic but zero deps)
      def speak_espeak(text, voice: "en", speed: 150, pitch: 50, play: true)
        output = File.join(Dir.tmpdir, "espeak_#{SecureRandom.hex(4)}.wav")

        cmd = ["espeak-ng", "-v", voice.to_s, "-s", speed.to_s,
               "-p", pitch.to_s, "-w", output, text]
        _out, _err, status = Open3.capture3(*cmd)
        return Result.err("espeak-ng failed.") unless status.success? && File.exist?(output)

        audio = File.binread(output)
        Playback.play_audio(output) if play
        FileUtils.rm_f(output)

        Result.ok(engine: :espeak, voice: voice, audio: audio, content_type: "audio/wav")
      end

      # Replicate TTS (paid cloud) -- MiniMax Speech-02 Turbo
      def speak_replicate(text, voice_id: nil, play: true)
        token = ENV.fetch("REPLICATE_API_TOKEN", nil)
        return Result.err("No REPLICATE_API_TOKEN.") unless token

        vid = voice_id || REPLICATE_VOICES.values.sample

        result = Replicate::Client.create_prediction(
          model: "minimax/speech-02-turbo",
          input: { text: text, voice_id: vid },
        )
        return Result.err("Replicate error: #{result[:error]}") if result[:error]

        poll = Replicate::Client.wait_for_completion(result[:id])
        return Result.err("Replicate poll error: #{poll[:error]}") if poll[:error]

        audio_url = poll[:output]
        return Result.err("No audio URL returned.") unless audio_url

        if play
          temp = File.join(Dir.tmpdir, "replicate_#{SecureRandom.hex(4)}.wav")
          Playback.download_and_play(audio_url, temp)
        end

        Result.ok(engine: :replicate, url: audio_url, voice: vid)
      rescue StandardError => err
        Result.err("Replicate error: #{err.message}")
      end
    end
  end
end
