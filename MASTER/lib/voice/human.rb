# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "tmpdir"

module Master
  module Voice
    # The `human` profile's synthesis: text is cut into clauses by Shaping, each
    # clause is spoken by the first engine that can (a local neural model for
    # its language, then Edge), trimmed of the engine's own edge silence, given
    # the pause Shaping assigned it, and optionally a soft breath before a long
    # sentence. Whole-utterance synthesis joins the clauses; Playback instead
    # speaks them one at a time so the first words start after one clause.
    #
    # Off unless the active profile sets `human_pipeline: true`, so the default
    # voice never passes through here. Every failure returns nil and the caller
    # keeps its ordinary path: engine missing, clause refused, ffmpeg absent.
    module Human
      RATE = 24_000
      # Playback deletes only files under this prefix, so every file the pipeline
      # hands it lives here.
      TMP = "/tmp"
      EDGE_TRIM = "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02," \
                  "areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.02,areverse"

      module_function

      def active? = Policy.human_pipeline?

      # Whole utterance as one mp3, or nil. Not shaped: Speech#shaped is the
      # caller's, so the chain is applied exactly once.
      def synthesize(text, voice: nil, rate: nil, pitch: nil, seed: nil)
        language = Language.detect(text)
        clauses = Shaping.plan(
          text, lang: language, seed: seed || ENV["MASTER_TTS_SEED"],
                base_rate: rate || Policy.default_rate, base_pitch: pitch || Policy.default_pitch
        )
        return if clauses.empty?

        parts = clauses.map { |clause| render(clause, language:, voice:, format: :wav) }
        return cleanup(parts) if parts.any?(&:nil?)

        join(parts)
      ensure
        cleanup(parts) if defined?(parts) && parts
      end

      # One clause as a finished mp3 (pause and breath included), or nil.
      def synthesize_clause(text:, rate:, pitch:, pause_ms: 0, breath: false, voice: nil)
        clause = Shaping::Clause.new(text:, pause_ms:, rate:, pitch:, breath:)
        render(clause, language: Language.detect(text), voice:, format: :mp3)
      end

      def render(clause, language:, voice:, format:)
        raw, gain = engine_audio(clause, language, voice)
        return unless raw

        finish(raw, clause, format, gain.to_f)
      ensure
        File.delete(raw) if defined?(raw) && raw && File.exist?(raw)
      end

      # First engine to produce audio for this clause: local entries for the
      # language, in declared order, then Edge. [raw file in any format, gain in
      # dB]; a local entry carries the gain that brings its raw level to Edge's,
      # so the profile chain sees the same input level whichever engine spoke.
      def engine_audio(clause, language, voice)
        LocalTts.entries_for(Shaping.language_key(clause.text, language)).each do |entry|
          next unless LocalTts.available?(entry)

          out = File.join(TMP, "m_human_#{SecureRandom.hex(6)}.wav")
          return [out, entry["gain_db"]] if LocalTts.synthesize(entry, clause.text, out)

          File.delete(out) if File.exist?(out)
        end
        edge_audio(clause, voice)
      end

      def edge_audio(clause, voice)
        return unless Speech.edge_tts_available?

        chosen = voice || Speech.voice_for_text(clause.text)
        path = Speech.synthesize_edge(
          clause.text, voice: Speech.resolve_voice(chosen),
                       style_config: { rate: clause.rate.to_s, pitch: clause.pitch.to_s }, shape: false
        )
        path && File.size?(path) ? [path, 0.0] : nil
      end

      # Local engines take rate here (atempo) because their command line has no
      # per-clause rate; Edge already applied its rate and pitch in synthesis.
      def finish(raw, clause, format, gain)
        out = File.join(TMP, "m_tts_#{SecureRandom.hex(8)}.#{format == :wav ? 'wav' : 'mp3'}")
        argv = ["ffmpeg", "-y", "-i", raw]
        breath = clause.breath ? Policy.breath : nil
        argv += ["-f", "lavfi", "-t", (breath["ms"] / 1000.0).to_s, "-i", Layers.noise_source(breath.fetch("seed"), breath["ms"] / 1000.0)] if breath
        argv += ["-filter_complex", graph(raw, clause, breath, gain), "-map", "[out]", *encoder(format), out]
        _o, _e, status = Master::Io::Exec.capture3(*argv)
        status.success? && File.size?(out) ? out : nil
      end

      def graph(raw, clause, breath, gain = 0.0)
        tempo = raw.end_with?(".wav") ? Engines.rate_factor(clause.rate) : 1.0
        voice = "[0:a]aformat=channel_layouts=mono,aresample=#{RATE},#{EDGE_TRIM}"
        voice += format(",atempo=%.4f", tempo) unless (tempo - 1.0).abs < 0.001
        voice += format(",volume=%.2fdB", gain) unless gain.zero?
        voice += format(",apad=pad_dur=%.3f", clause.pause_ms.to_f / 1000)
        return "#{voice}[out]" unless breath

        "#{voice}[v];#{Layers.breath_filter(breath, 1, stereo: false)}[br];[br][v]concat=n=2:v=0:a=1[out]"
      end

      def encoder(format)
        format == :wav ? ["-ar", RATE.to_s, "-ac", "1"] : ["-ar", RATE.to_s, "-ac", "1", "-codec:a", "libmp3lame", "-q:a", "2"]
      end

      def join(parts)
        out = File.join(TMP, "m_tts_#{SecureRandom.hex(8)}.mp3")
        inputs = parts.flat_map { |path| ["-i", path] }
        graph = "#{parts.each_index.map { |i| "[#{i}:a]" }.join}concat=n=#{parts.size}:v=0:a=1[out]"
        _o, _e, status = Master::Io::Exec.capture3(
          "ffmpeg", "-y", *inputs, "-filter_complex", graph, "-map", "[out]", "-ar", RATE.to_s, "-ac", "1",
          "-codec:a", "libmp3lame", "-q:a", "2", out
        )
        status.success? && File.size?(out) ? out : nil
      end

      def cleanup(paths)
        Array(paths).compact.each { |path| File.delete(path) if File.exist?(path) }
        nil
      end
    end
  end
end
