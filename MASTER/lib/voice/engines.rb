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
      # is no longer forced first by `attempt?`'s always-try-on-OpenBSD gate,
      # but that's a network round-trip to a third-party inference API on
      # every single phrase -- on a 1-CPU VPS with a serial synth queue, that
      # was the dominant source of "TTS is slow." It stays in the chain as a
      # fallback if edge-tts is ever unavailable.
      OPENBSD_CHAIN = %w[edge_melodic edge say].freeze
      DEFAULT_CHAIN = %w[mlx chatterbox edge_melodic edge say].freeze
      # Native macOS `say` is only a controlled fallback. A bare `say` invocation
      # can select the host default voice, which is allowed to be a different
      # speaker. Keep only deliberate aliases here; an unmapped neural voice must
      # fail this engine and let the caller choose its other safe fallbacks.
      MACOS_VOICE_FALLBACKS = { jenny: "Samantha", andrew: "Alex" }.freeze
      # major*10+minor version-code encoding (e.g. Python 3.10 -> 310); MLX needs 3.10+.
      MIN_MLX_PYTHON_VERSION_CODE = 310

      module_function

      def openbsd? = RUBY_PLATFORM.include?("openbsd")

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
        when "mlx" then synth_mlx(text, out_path, cfg, emotion, rate:, pitch:)
        when "chatterbox" then synth_chatterbox(text, out_path, cfg, emotion, rate:, pitch:)
        when "replicate_kokoro" then synth_replicate_kokoro(text, out_path, cfg, emotion)
        when "edge_melodic" then synth_edge_melodic(text, out_path, melody, voice, rate, pitch)
        when "edge" then synth_edge(text, out_path, voice, rate, pitch)
        when "say" then synth_say(text, out_path, voice:)
        else false
        end
      end

      def replicate_token?
        !Io::ReplicateClient.load_token.to_s.strip.empty?
      end

      def synth_replicate_kokoro(text, out_path, cfg, emotion)
        enriched = Enrich.apply(text, emotion, tags: cfg["paralinguistic_tags"] == true)
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

      def synth_mlx(text, out_path, cfg, emotion, rate: nil, pitch: nil)
        py = mlx_python
        return false unless py

        model = cfg["mlx_model"] || "mlx-community/Kokoro-82M-bf16"
        voice = cfg["mlx_voice"] || "af_bella"
        speed = ((cfg["mlx_speed"] || 1.15).to_f * rate_factor(rate)).clamp(0.80, 1.20)
        enriched = Enrich.apply(text, emotion, tags: cfg["paralinguistic_tags"] == true)
        out_dir = File.dirname(out_path)
        FileUtils.mkdir_p(out_dir)

        # Chatterbox on MLX is the expressive local path. Its voice argument is
        # intentionally ignored by the model; speaker identity comes from
        # precomputed conditionals or a reference clip. Use the Python API so
        # emotion controls and the language code actually reach Chatterbox.
        unless model.downcase.include?("chatterbox")
          bin = cfg["mlx_bin"].to_s.strip
          bin = "mlx_audio.tts.generate" if bin.empty?
          attempted, result = try_mlx_cli(bin, model, enriched, voice, speed, out_dir, out_path, pitch)
          return result if attempted
        end

        result = try_mlx_python_api(
          py, model, enriched, voice, speed, out_path,
          emotion:,
          rate:,
          pitch:,
          reference_clip: cfg["reference_clip"],
          cfg:,
        )
        result ? realize_pitch(result, pitch) : false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.synth_mlx")
        false
      end

      def try_mlx_cli(bin, model, enriched, voice, speed, out_dir, out_path, pitch)
        return [false, nil] unless system("which", bin, out: File::NULL, err: File::NULL)

        ok = system(
          bin, "--model", model, "--text", enriched, "--voice", voice, "--speed", speed.to_s,
          "--output_path", out_dir, "--file_prefix", "master",
          out: File::NULL, err: File::NULL
        )
        candidate = Dir.glob(File.join(out_dir, "master*.wav")).max_by { |f| File.mtime(f) }
        if ok && candidate
          converted = convert_to_mp3(candidate, out_path)
          return [true, converted ? realize_pitch(out_path, pitch) : false]
        end

        [false, nil]
      end

      def try_mlx_python_api(py, model, enriched, voice, speed, out_path, emotion:, rate:, pitch:, reference_clip:, cfg:)
        wav = out_path.sub(/\.mp3\z/, ".wav")
        ref = reference_clip.to_s.strip
        ref = File.expand_path(ref) unless ref.empty?
        ref = nil unless File.file?(ref)
        exag = emotion.fetch(:exaggeration) { cfg["exaggeration"] || 0.45 }.to_f.clamp(0.0, 1.0)
        cfg_weight = emotion.fetch(:cfg_weight) { cfg.fetch("cfg_weight", 0.42) }.to_f.clamp(0.0, 1.0)
        temperature = cfg.fetch("temperature", 0.8).to_f
        repetition_penalty = cfg.fetch("repetition_penalty", 1.2).to_f
        min_p = cfg.fetch("min_p", 0.05).to_f
        top_p = cfg.fetch("top_p", 1.0).to_f
        lang_code = "en"

        py_script = <<~PY
          import numpy as np
          import soundfile as sf
          from mlx_audio.tts.utils import load_model

          model = load_model(#{model.inspect})
          kwargs = {
              "text": #{enriched.inspect},
              "exaggeration": #{exag},
              "cfg_weight": #{cfg_weight},
              "temperature": #{temperature},
              "repetition_penalty": #{repetition_penalty},
              "min_p": #{min_p},
              "top_p": #{top_p},
              "lang_code": #{lang_code.inspect},
              "verbose": False,
          }
          ref_audio = #{ref.inspect}
          kwargs["ref_audio"] = ref_audio if ref_audio else None
          chunks = []
          sample_rate = None
          for result in model.generate(**kwargs):
              chunk = np.asarray(result.audio).reshape(-1)
              if chunk.size:
                  chunks.append(chunk)
              sample_rate = result.sample_rate
          if not chunks or sample_rate is None:
              raise RuntimeError("mlx generated no audio")
          audio = np.concatenate(chunks)
          sf.write(#{wav.inspect}, audio, int(sample_rate))
        PY
        _out, _err, status = Master::Io::Exec.capture3(py, "-c", py_script)
        return convert_to_mp3(wav, out_path) if status.success? && File.size?(wav)

        false
      end

      def synth_chatterbox(text, out_path, cfg, emotion, rate: nil, pitch: nil)
        enriched = Enrich.apply(text, emotion, tags: cfg["paralinguistic_tags"] == true)
        wav = out_path.sub(/\.mp3\z/, ".wav")
        ref = cfg["reference_clip"].to_s
        ref = File.expand_path(ref) unless ref.empty?
        device = cfg["chatterbox_device"] || "mps"
        exag = emotion.fetch(:exaggeration) { cfg["exaggeration"] || 0.55 }
        cfg_weight = emotion.fetch(:cfg_weight) { cfg.fetch("cfg_weight", 0.42) }

        py = chatterbox_py_script(enriched, device, ref, wav, exaggeration: exag, cfg_weight:)
        _out, _err, status = Master::Io::Exec.capture3("python3", "-c", py)
        if status.success? && File.size?(wav)
          converted = convert_to_mp3(wav, out_path)
          return realize_audio_prosody(out_path, rate:, pitch:) if converted && File.size?(out_path)
        end

        false
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.synth_chatterbox")
        false
      end

      def chatterbox_py_script(enriched, device, ref, wav, exaggeration:, cfg_weight:)
        <<~PY
          import torchaudio as ta
          from chatterbox.mtl_tts import ChatterboxMultilingualTTS
          model = ChatterboxMultilingualTTS.from_pretrained(device=#{device.inspect}, t3_model="v3")
          kwargs = {
              "language_id": "en",
              "exaggeration": #{exaggeration.to_f},
              "cfg_weight": #{cfg_weight.to_f},
          }
          ref = #{ref.inspect}
          kwargs["audio_prompt_path"] = ref if ref
          wav = model.generate(#{enriched.inspect}, **kwargs)
          ta.save(#{wav.inspect}, wav, model.sr)
        PY
      end

      def rate_factor(rate)
        percent = rate.to_s.delete("%").to_f
        (1.0 + (percent / 100.0)).clamp(0.80, 1.20)
      end

      def pitch_delta_hz(pitch)
        pitch.to_s.delete("Hz").to_f
      end

      def pitch_ratio(pitch)
        delta = pitch_delta_hz(pitch)
        return 1.0 if delta.zero?

        reference = Speech::Policy.prosody.fetch("pitch_reference_hz", 180).to_f.clamp(120.0, 260.0)
        ((reference + delta) / reference).clamp(0.85, 1.15)
      end

      def realize_audio_prosody(path, rate:, pitch:)
        return path unless path && File.size?(path)
        return path if rate_factor(rate) == 1.0 && pitch_delta_hz(pitch).zero?
        return path unless ffmpeg?

        filters = []
        filters << "atempo=#{format("%.5f", rate_factor(rate))}" if rate_factor(rate) != 1.0
        if pitch_delta_hz(pitch) != 0.0 && rubberband?
          filters << "rubberband=pitch=#{format("%.6f", pitch_ratio(pitch))}"
        end
        return path if filters.empty?

        out = path.sub(/\.mp3\\z/, "_prosody.mp3")
        ok = system(
          "ffmpeg", "-y", "-i", path, "-af", filters.join(","),
          "-codec:a", "libmp3lame", "-q:a", "2", out,
          out: File::NULL, err: File::NULL,
        )
        return path unless ok && File.size?(out)

        File.delete(path) if path != out && File.exist?(path)
        out
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.realize_audio_prosody")
        path
      end

      def realize_pitch(path, pitch)
        return path if pitch_delta_hz(pitch).zero?
        return path unless path && File.size?(path) && ffmpeg? && rubberband?

        out = path.sub(/\.mp3\\z/, "_pitch.mp3")
        ok = system(
          "ffmpeg", "-y", "-i", path,
          "-af", "rubberband=pitch=#{format("%.6f", pitch_ratio(pitch))}",
          "-codec:a", "libmp3lame", "-q:a", "2", out,
          out: File::NULL, err: File::NULL,
        )
        return path unless ok && File.size?(out)

        File.delete(path) if path != out && File.exist?(path)
        out
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Engines.realize_pitch")
        path
      end

      def rubberband?
        return @rubberband unless @rubberband.nil?

        out, status = Master::Io::Exec.capture2("ffmpeg", "-filters", err: File::NULL)
        @rubberband = status.success? && out.to_s.lines.any? { |line| line.include?("rubberband") }
      rescue StandardError
        @rubberband = false
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

        # A melodic plan is one spoken utterance. Without ffmpeg there is no safe
        # way to join its phrase files into that utterance. Returning phrase one
        # and playing the rest separately made the caller observe a truncated
        # sentence, and on a host with another player it could overlap the normal
        # playback path. Fail this engine cleanly so the chain can fall through to
        # a complete non-melodic engine instead.
        report_missing_ffmpeg("synth_edge_melodic", "melodic phrases not joined; falling through to next engine")
        parts.each { |(path, _pause)| File.delete(path) if File.exist?(path) }
        false
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
        path = Speech.synthesize_edge(text, voice:, style_config: { rate:, pitch: }, shape: false)
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
        return unless status.success? && rate.to_i.positive? && channels.to_i.positive?

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
        sequence.each { |p| File.delete(p) if File.exist?(p) } # scan: intentional — a named list of temp files this call created
        File.delete(list) if File.exist?(list)
        ok && File.size?(out_path)
      end

      def synth_say(text, out_path, voice: nil, rate: nil)
        aiff = out_path.sub(/\.[^.]+\z/, ".aiff")
        voice_key = if voice
                      Speech::VOICE_ALIASES.key(voice.to_s) || voice.to_sym
                    else
                      Speech.voice_for_text(text).to_sym
                    end
        mac_voice = MACOS_VOICE_FALLBACKS[voice_key]
        return false unless mac_voice

        pct = rate.to_s.match?(/\A[+-]?\d+(?:\.\d+)?%\z/) ? rate.to_f : 0.0
        spd = (175 * (1.0 + (pct / 100.0))).round.clamp(120, 220)
        ok = system("say", "-v", mac_voice, "-r", spd.to_s, "-o", aiff, text.to_s,
                    out: File::NULL, err: File::NULL)
        return false unless ok && File.size?(aiff)

        if system("which", "afconvert", out: File::NULL, err: File::NULL)
          system("afconvert", "-f", "m4af", "-d", "aac", aiff, out_path, out: File::NULL, err: File::NULL)
          File.delete(aiff)
          File.size?(out_path)
        else
          FileUtils.mv(aiff, out_path)
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
          context: "Engines.#{where}", severity: :load_bearing,
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
