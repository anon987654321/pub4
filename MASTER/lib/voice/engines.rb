# frozen_string_literal: true

require "open3"
require "fileutils"

module Master
  module Voice
    # Multi-engine TTS registry — mlx, chatterbox, edge_melodic, edge, say.
    module Engines
      module_function

      def available?(name, cfg)
        case name.to_s
        when "mlx" then mlx_cli?(cfg)
        when "chatterbox" then chatterbox_cli?
        when "replicate_kokoro" then replicate_token?
        when "edge", "edge_melodic" then Speech.edge_tts_available?
        when "say" then system("which", "say", out: File::NULL, err: File::NULL)
        else false
        end
      end

      def synth(name, text:, out_path:, cfg:, emotion:, melody:, voice:, rate:, pitch:)
        case name.to_s
        when "mlx" then synth_mlx(text, out_path, cfg, emotion)
        when "chatterbox" then synth_chatterbox(text, out_path, cfg, emotion)
        when "replicate_kokoro" then synth_replicate_kokoro(text, out_path, cfg, emotion)
        when "edge_melodic" then synth_edge_melodic(text, out_path, melody, voice, rate, pitch)
        when "edge" then synth_edge(text, out_path, voice, rate, pitch)
        when "say" then synth_say(text, out_path)
        else false
        end
      end

      def replicate_token?
        !Reach::ReplicateClient.load_token.to_s.strip.empty?
      end

      def synth_replicate_kokoro(text, out_path, cfg, emotion)
        enriched = Enrich.apply(text, emotion)
        model = cfg["replicate_model"] || "jaaari/kokoro-82m"
        kokoro_voice = cfg["replicate_voice"] || "af_bella"
        speed = (cfg["replicate_speed"] || 1.18).to_f
        client = Reach::ReplicateClient.new
        output = client.predict(model, { text: enriched, voice: kokoro_voice, speed: speed })
        url = Array(output).flatten.first.to_s
        return false if url.strip.empty?

        tmp = out_path.sub(/\.mp3\z/, "_replicate#{File.extname(url)}")
        tmp = "#{tmp}.wav" if File.extname(tmp).empty?
        Reach::VideoPost.download_url(url, tmp)
        return FileUtils.cp(tmp, out_path) if tmp.end_with?(".mp3") && File.size?(tmp)

        convert_to_mp3(tmp, out_path)
      rescue StandardError
        false
      ensure
        File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp) && tmp != out_path
      end

      def mlx_python
        cfg_bin = ENV["MASTER_MLX_PYTHON"].to_s.strip
        return cfg_bin if cfg_bin != "" && File.executable?(cfg_bin)

        %w[python3.12 python3.11 python3].each do |bin|
          next unless system("which", bin, out: File::NULL, err: File::NULL)

          ver = `#{bin} -c 'import sys; print(sys.version_info[:major]*10+sys.version_info[:minor])' 2>/dev/null`.strip.to_i
          return bin if ver >= 310
        end
        nil
      end

      def mlx_cli?(cfg)
        py = mlx_python
        return false unless py

        bin = cfg["mlx_bin"].to_s.strip
        return File.executable?(bin) if bin != ""

        return true if system("which", "mlx_audio.tts.generate", out: File::NULL, err: File::NULL)

        _out, status = Open3.capture2(py, "-c", "import mlx_audio.tts", err: File::NULL)
        status.success?
      end

      def chatterbox_cli?
        _out, status = Open3.capture2("python3", "-c", "import chatterbox", err: File::NULL)
        status.success?
      end

      def synth_mlx(text, out_path, cfg, emotion)
        py = mlx_python
        return false unless py

        model = cfg["mlx_model"] || "mlx-community/Kokoro-82M-bf16"
        voice = cfg["mlx_voice"] || "af_bella"
        speed = (cfg["mlx_speed"] || 1.15).to_f
        enriched = Enrich.apply(text, emotion)
        out_dir = File.dirname(out_path)
        FileUtils.mkdir_p(out_dir)
        bin = cfg["mlx_bin"].to_s.strip
        bin = "mlx_audio.tts.generate" if bin.empty?

        if system("which", bin, out: File::NULL, err: File::NULL)
          ok = system(
            bin, "--model", model, "--text", enriched, "--voice", voice, "--speed", speed.to_s,
            "--output_path", out_dir, "--file_prefix", "master",
            out: File::NULL, err: File::NULL
          )
          candidate = Dir.glob(File.join(out_dir, "master*.wav")).max_by { |f| File.mtime(f) }
          return convert_to_mp3(candidate, out_path) if ok && candidate
        end

        wav = out_path.sub(/\.mp3\z/, ".wav")
        py_script = <<~PY
          import numpy as np
          import soundfile as sf
          from mlx_audio.tts.utils import load_model
          model = load_model(#{model.inspect})
          audio = None
          for result in model.generate(#{enriched.inspect}, voice=#{voice.inspect}, speed=#{speed}):
              audio = np.array(result.audio)
          if audio is None:
              raise RuntimeError("mlx generated no audio")
          sf.write(#{wav.inspect}, audio, #{cfg["mlx_sample_rate"] || 24_000})
        PY
        _out, _err, status = Open3.capture3(py, "-c", py_script)
        return convert_to_mp3(wav, out_path) if status.success? && File.size?(wav)

        false
      rescue StandardError
        false
      end

      def synth_chatterbox(text, out_path, cfg, emotion)
        enriched = Enrich.apply(text, emotion)
        wav = out_path.sub(/\.mp3\z/, ".wav")
        ref = cfg["reference_clip"].to_s
        ref = File.expand_path(ref) unless ref.empty?
        device = cfg["chatterbox_device"] || "mps"
        exag = emotion[:exaggeration] || cfg["exaggeration"] || 0.55

        py = <<~PY
          import torchaudio as ta
          from chatterbox.mtl_tts import ChatterboxMultilingualTTS
          model = ChatterboxMultilingualTTS.from_pretrained(device=#{device.inspect}, t3_model="v3")
          kwargs = {"language_id": "en"}
          ref = #{ref.inspect}
          kwargs["audio_prompt_path"] = ref if ref
          wav = model.generate(#{enriched.inspect}, **kwargs)
          ta.save(#{wav.inspect}, wav, model.sr)
        PY
        _out, _err, status = Open3.capture3("python3", "-c", py)
        return convert_to_mp3(wav, out_path) if status.success? && File.size?(wav)

        false
      rescue StandardError
        false
      end

      def synth_edge(text, out_path, voice, rate, pitch)
        copy_if_synthesized(text, out_path, voice, rate, pitch)
      end

      def synth_edge_melodic(text, out_path, melody, voice, rate, pitch)
        plan = melody[:phrases]
        return synth_edge(text, out_path, voice, rate, pitch) if plan.nil? || plan.empty?

        tmp_dir = File.join(Master::ROOT, ".master", "melodic")
        FileUtils.mkdir_p(tmp_dir)
        parts = []

        plan.each_with_index do |phrase, i|
          part = File.join(tmp_dir, "part_#{Process.pid}_#{i}.mp3")
          ok = copy_if_synthesized(phrase[:text], part, voice, phrase[:rate] || rate, phrase[:pitch] || pitch)
          parts << part if ok
          sleep((phrase[:pause_ms] || 0) / 1000.0) if i.positive? && ok
        end

        return false if parts.empty?
        return FileUtils.cp(parts.first, out_path) if parts.length == 1
        return concat_mp3(parts, out_path, tmp_dir) if ffmpeg?

        FileUtils.cp(parts.first, out_path)
        parts.drop(1).each { |p| system("afplay", p, out: File::NULL, err: File::NULL); File.delete(p) }
        File.size?(out_path)
      rescue StandardError
        false
      end

      def copy_if_synthesized(text, out_path, voice, rate, pitch)
        path = Speech.synthesize_edge(text, voice: voice, style_config: { rate: rate, pitch: pitch })
        return false unless path && File.size?(path)

        FileUtils.cp(path, out_path)
        File.delete(path)
        true
      end

      def concat_mp3(parts, out_path, tmp_dir)
        list = File.join(tmp_dir, "concat_#{Process.pid}.txt")
        File.write(list, parts.map { |p| "file '#{p}'" }.join("\n"))
        ok = system("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", out_path,
                    out: File::NULL, err: File::NULL)
        parts.each { |p| File.delete(p) if File.exist?(p) }
        File.delete(list) if File.exist?(list)
        ok && File.size?(out_path)
      end

      def synth_say(text, out_path)
        aiff = out_path.sub(/\.mp3\z/, ".aiff")
        spd = 175 + rand(25)
        ok = system("say", "-v", "Samantha", "-r", spd.to_s, "-o", aiff, text.to_s, out: File::NULL, err: File::NULL) ||
             system("say", "-o", aiff, text.to_s, out: File::NULL, err: File::NULL)
        return false unless ok && File.size?(aiff)

        if system("which", "afconvert", out: File::NULL, err: File::NULL)
          system("afconvert", "-f", "m4af", "-d", "aac", aiff, out_path, out: File::NULL, err: File::NULL)
          File.delete(aiff)
          File.size?(out_path)
        else
          FileUtils.mv(aiff, out_path.sub(/\.mp3\z/, ".aiff"))
          true
        end
      rescue StandardError
        false
      end

      def convert_to_mp3(wav_path, mp3_path)
        return false unless wav_path && File.size?(wav_path)

        if ffmpeg?
          ok = system("ffmpeg", "-y", "-i", wav_path, mp3_path, out: File::NULL, err: File::NULL)
          File.delete(wav_path) if ok
          return ok && File.size?(mp3_path)
        end

        FileUtils.cp(wav_path, mp3_path.sub(/\.mp3\z/, ".wav"))
        true
      end

      def ffmpeg?
        system("which", "ffmpeg", out: File::NULL, err: File::NULL)
      end
    end
  end
end