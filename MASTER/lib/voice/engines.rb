# frozen_string_literal: true

require "open3"
require "fileutils"

module Master
  module Voice
    # Multi-engine TTS registry — mlx, chatterbox, edge_melodic, edge, say.
    module Engines
      # edge_melodic/edge lead the chain: they're a fast local subprocess and
      # already speak whatever data/voice.yml names (do not repeat the voice
      # here — that is how the last two switches left the tree stale). Kokoro
      # used to be forced first via `attempt?`'s always-try-on-OpenBSD gate,
      # but that's a network round-trip to a third-party inference API on
      # every single phrase -- on a 1-CPU VPS with a serial synth queue, that
      # was the dominant source of "TTS is slow." It stays in the chain as a
      # fallback if edge-tts is ever unavailable.
      OPENBSD_CHAIN = %w[edge_melodic edge replicate_kokoro say].freeze
      DEFAULT_CHAIN = %w[mlx chatterbox replicate_kokoro edge_melodic edge say].freeze
      # major*10+minor version-code encoding (e.g. Python 3.10 -> 310); MLX needs 3.10+.
      MIN_MLX_PYTHON_VERSION_CODE = 310

      module_function

      def openbsd? = RUBY_PLATFORM.include?("openbsd")

      def default_engine_chain
        openbsd? ? OPENBSD_CHAIN.join(",") : DEFAULT_CHAIN.join(",")
      end

      # Gate preflight; on OpenBSD always attempt Replicate Kokoro and fall through on failure.
      def attempt?(name, cfg)
        return true if name.to_s == "replicate_kokoro" && openbsd?

        available?(name, cfg)
      end

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
        !Io::ReplicateClient.load_token.to_s.strip.empty?
      end

      def synth_replicate_kokoro(text, out_path, cfg, emotion)
        enriched = Enrich.apply(text, emotion)
        client = Io::ReplicateClient.new
        url = predict_kokoro_url(client, cfg, enriched)
        return false unless url

        tmp = out_path.sub(/\.mp3\z/, "_replicate#{File.extname(url)}")
        tmp = "#{tmp}.wav" if File.extname(tmp).empty?
        client.download_url(url, tmp)
        finalize_kokoro_output(tmp, out_path)
      rescue StandardError => e
        Ground::Swallow.log(e, context: "Engines.synth_replicate_kokoro")
        false
      ensure
        File.delete(tmp) if defined?(tmp) && tmp && File.exist?(tmp) && tmp != out_path
      end

      def predict_kokoro_url(client, cfg, enriched)
        model = cfg["replicate_model"] || "jaaari/kokoro-82m"
        kokoro_voice = cfg["replicate_voice"] || "af_bella"
        speed = (cfg["replicate_speed"] || 1.18).to_f
        output = client.predict(model, { text: enriched, voice: kokoro_voice, speed: })
        return if output.nil?

        url = Array(output).flatten.first.to_s
        url.strip.empty? ? nil : url
      end

      def finalize_kokoro_output(tmp, out_path)
        return FileUtils.cp(tmp, out_path) if tmp.end_with?(".mp3") && File.size?(tmp)

        if convert_to_mp3(tmp, out_path)
          File.size?(out_path)
        elsif File.extname(tmp) == ".mp3" && File.size?(tmp)
          FileUtils.cp(tmp, out_path)
          File.size?(out_path)
        end
      end

      def mlx_python
        cfg_bin = ENV["MASTER_MLX_PYTHON"].to_s.strip
        return cfg_bin if cfg_bin != "" && File.executable?(cfg_bin)

        %w[python3.12 python3.11 python3].each do |bin|
          next unless system("which", bin, out: File::NULL, err: File::NULL)

          out, _status = Open3.capture2(bin, "-c", "import sys; print(sys.version_info[:major]*10+sys.version_info[:minor])", err: File::NULL)
          ver = out.strip.to_i
          return bin if ver >= MIN_MLX_PYTHON_VERSION_CODE
        end
        nil
      end

      def mlx_cli?(cfg)
        py = mlx_python
        return false unless py

        bin = cfg["mlx_bin"].to_s.strip
        return File.executable?(bin) if bin != ""

        return true if system("which", "mlx_audio.tts.generate", out: File::NULL, err: File::NULL)

        _out, status = Master::Io::Exec.capture2(py, "-c", "import mlx_audio.tts", err: File::NULL)
        status.success?
      end

      def chatterbox_cli?
        _out, status = Master::Io::Exec.capture2("python3", "-c", "import chatterbox", err: File::NULL)
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

        attempted, result = try_mlx_cli(bin, model, enriched, voice, speed, out_dir, out_path)
        return result if attempted

        try_mlx_python_api(py, model, enriched, voice, speed, out_path)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.synth_mlx")
        false
      end

      def try_mlx_cli(bin, model, enriched, voice, speed, out_dir, out_path)
        return [false, nil] unless system("which", bin, out: File::NULL, err: File::NULL)

        ok = system(
          bin, "--model", model, "--text", enriched, "--voice", voice, "--speed", speed.to_s,
          "--output_path", out_dir, "--file_prefix", "master",
          out: File::NULL, err: File::NULL
        )
        candidate = Dir.glob(File.join(out_dir, "master*.wav")).max_by { |f| File.mtime(f) }
        return [true, convert_to_mp3(candidate, out_path)] if ok && candidate

        [false, nil]
      end

      def try_mlx_python_api(py, model, enriched, voice, speed, out_path)
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
        PY
        _out, _err, status = Master::Io::Exec.capture3(py, "-c", py_script)
        return convert_to_mp3(wav, out_path) if status.success? && File.size?(wav)

        false
      end

      def synth_chatterbox(text, out_path, cfg, emotion)
        enriched = Enrich.apply(text, emotion)
        wav = out_path.sub(/\.mp3\z/, ".wav")
        ref = cfg["reference_clip"].to_s
        ref = File.expand_path(ref) unless ref.empty?
        device = cfg["chatterbox_device"] || "mps"
        exag = emotion.fetch(:exaggeration) { cfg["exaggeration"] || 0.55 }

        py = chatterbox_py_script(enriched, device, ref, wav)
        _out, _err, status = Master::Io::Exec.capture3("python3", "-c", py)
        return convert_to_mp3(wav, out_path) if status.success? && File.size?(wav)

        false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.synth_chatterbox")
        false
      end

      def chatterbox_py_script(enriched, device, ref, wav)
        <<~PY
          import torchaudio as ta
          from chatterbox.mtl_tts import ChatterboxMultilingualTTS
          model = ChatterboxMultilingualTTS.from_pretrained(device=#{device.inspect}, t3_model="v3")
          kwargs = {"language_id": "en"}
          ref = #{ref.inspect}
          kwargs["audio_prompt_path"] = ref if ref
          wav = model.generate(#{enriched.inspect}, **kwargs)
          ta.save(#{wav.inspect}, wav, model.sr)
        PY
      end

      def synth_edge(text, out_path, voice, rate, pitch)
        copy_if_synthesized(text, out_path, voice, rate, pitch)
      end

      def synth_edge_melodic(text, out_path, melody, voice, rate, pitch)
        plan = melody[:phrases]
        return synth_edge(text, out_path, voice, rate, pitch) if plan.nil? || plan.empty?

        tmp_dir = File.join(Master::ROOT, ".master", "melodic")
        FileUtils.mkdir_p(tmp_dir)
        parts = synthesize_phrase_parts(plan, tmp_dir, voice, rate, pitch)

        return false if parts.empty?
        return copy_single_part(parts, out_path) if parts.length == 1
        return concat_mp3(parts, out_path, tmp_dir) if ffmpeg?

        # Without ffmpeg the remaining phrases cannot be joined, and afplay does
        # not exist on the deploy host — so the fallback below is silent there
        # and the caller receives phrase one alone. Load-bearing on purpose:
        # ffmpeg is what makes phrase rendering safe to enable at all.
        report_missing_ffmpeg("synth_edge_melodic", "phrases played separately, output holds only the first")
        FileUtils.cp(parts.first.first, out_path)
        parts.drop(1).each do |(path, _pause)|
          system("afplay", path, out: File::NULL, err: File::NULL)
          File.delete(path)
        end
        File.size?(out_path)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.synth_edge_melodic")
        false
      end

      # Returns [path, pause_ms_before] per rendered phrase. The pause used to be
      # `sleep(pause_ms / 1000.0)` right here, which spent the rest as latency in
      # the synthesis loop and put nothing in the audio — concat_mp3 then joined
      # the phrases back to back. Melody planned rests that were never audible.
      def synthesize_phrase_parts(plan, tmp_dir, voice, rate, pitch)
        parts = []
        plan.each_with_index do |phrase, i|
          part = File.join(tmp_dir, "part_#{Process.pid}_#{i}.mp3")
          ok = copy_if_synthesized(phrase[:text], part, phrase.fetch(:voice, voice),
                                   phrase.fetch(:rate, rate), phrase.fetch(:pitch, pitch))
          parts << [part, i.zero? ? 0 : phrase.fetch(:pause_ms, 0).to_i] if ok
        end
        parts
      end

      def copy_single_part(parts, out_path)
        FileUtils.cp(parts.first.first, out_path)
        File.size?(out_path)
      end

      def copy_if_synthesized(text, out_path, voice, rate, pitch)
        path = Speech.synthesize_edge(text, voice:, style_config: { rate:, pitch: })
        return false unless path && File.size?(path)

        FileUtils.cp(path, out_path)
        File.delete(path)
        true
      end

      # Silence is generated to match the speech parts rather than at a fixed
      # format, because the concat demuxer runs with -c copy: an mp3 at a
      # different sample rate or channel count joins without an error and plays
      # back at the wrong speed from that point on. Probed once, from the first
      # part, so a change in the Edge output format follows automatically.
      def silence_format(part)
        out, _err, status = Master::Io::Exec.capture3(
          "ffprobe", "-v", "error", "-select_streams", "a:0",
          "-show_entries", "stream=sample_rate,channels,bit_rate",
          "-of", "default=noprint_wrappers=1:nokey=1", part
        )
        rate, channels, bitrate = out.to_s.split("\n").map(&:strip)
        return nil unless status.success? && rate.to_i.positive? && channels.to_i.positive?

        { rate: rate.to_i, channels: channels.to_i, bitrate: bitrate.to_i.positive? ? bitrate.to_i : 48_000 }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.silence_format")
        nil
      end

      def silence_part(ms, fmt, tmp_dir, index)
        path = File.join(tmp_dir, "rest_#{Process.pid}_#{index}.mp3")
        layout = fmt[:channels] > 1 ? "stereo" : "mono"
        ok = system("ffmpeg", "-y", "-f", "lavfi",
                    "-i", "anullsrc=r=#{fmt[:rate]}:cl=#{layout}",
                    "-t", format("%.3f", ms / 1000.0),
                    "-b:a", fmt[:bitrate].to_s, "-ar", fmt[:rate].to_s, "-ac", fmt[:channels].to_s,
                    path, out: File::NULL, err: File::NULL)
        ok && File.size?(path) ? path : nil
      end

      # parts is [[path, pause_ms_before], ...].
      def concat_sequence(parts, tmp_dir)
        fmt = silence_format(parts.first.first)
        sequence = []
        parts.each_with_index do |(path, pause_ms), i|
          rest = (fmt && pause_ms.positive? ? silence_part(pause_ms, fmt, tmp_dir, i) : nil)
          sequence << rest if rest
          sequence << path
        end
        sequence
      end

      def concat_mp3(parts, out_path, tmp_dir)
        sequence = concat_sequence(parts, tmp_dir)
        list = File.join(tmp_dir, "concat_#{Process.pid}.txt")
        File.write(list, sequence.map { |p| "file '#{p}'" }.join("\n"))
        ok = system("ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", out_path,
                    out: File::NULL, err: File::NULL)
        sequence.each { |p| File.delete(p) if File.exist?(p) }
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
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.synth_say")
        false
      end

      def convert_to_mp3(wav_path, mp3_path)
        return false unless wav_path && File.size?(wav_path)

        if ffmpeg?
          ok = system("ffmpeg", "-y", "-i", wav_path, mp3_path, out: File::NULL, err: File::NULL)
          File.delete(wav_path) if ok
          return ok && File.size?(mp3_path)
        end

        report_missing_ffmpeg("convert_to_mp3", "left as WAV at #{mp3_path.sub(/\.mp3\z/, ".wav")}")
        FileUtils.cp(wav_path, mp3_path.sub(/\.mp3\z/, ".wav"))
        true
      end

      # Both ffmpeg fallbacks used to return quietly, so a host without ffmpeg
      # served un-concatenated or unconverted audio with nothing logged anywhere
      # — correct on a Mac, degraded on the VPS, indistinguishable from working.
      def report_missing_ffmpeg(where, consequence)
        Master::Ground::Swallow.log(
          RuntimeError.new("ffmpeg not on PATH — #{consequence}"),
          context: "Engines.#{where}", severity: :load_bearing
        )
      end

      # Memoized: this is asked once per synthesized phrase, and each ask was a
      # fork+exec of which(1).
      def ffmpeg?
        return @ffmpeg unless @ffmpeg.nil?

        @ffmpeg = system("which", "ffmpeg", out: File::NULL, err: File::NULL) || false
      end
    end
  end
end
