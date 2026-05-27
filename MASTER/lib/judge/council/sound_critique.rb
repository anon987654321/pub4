# frozen_string_literal: true

module Master
  module Judge
  module Council
    class SoundCritique
      COUNCIL_PATH = File.join(Master::ROOT, "data", "council.yml").freeze
      MAX_FILE_BYTES = 24_576

      SOUND_PANEL = [
        "Electronic Music Producer",
        "Hip-Hop Producer",
        "User Advocate",
        "Accessibility",
        "Layperson",
        "Skeptic"
      ].freeze

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus = event_bus
      end

      def run
        preset = load_preset
        panel = build_panel(preset)
        payload = build_payload(preset)
        @bus&.publish(:sound_critique_start, files: payload[:files], personas: panel.map(&:name))

        deliberation = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
        result = deliberation.review(payload[:combined], context: sound_context)
        return result unless result.ok?

        feedback = result.value!
        ideas = Ideation.new(agent: @agent, event_bus: @bus).ideate(
          "Generate concrete improvements for MASTER sound design, voice playback, sonic timing, and audio feedback.",
          constraints: sound_constraints,
          cycles: (preset.dig("cycles") || 2).to_i
        )
        return ideas if ideas.err?

        picks = cherry_pick(feedback, ideas.value.fetch(:final, ""))
        @bus&.publish(:sound_critique_done, cherry_picks: picks.size)
        Master::Result.ok({ feedback: feedback, ideas: ideas.value, cherry_picks: picks })
      end

      private

      def load_preset
        data = File.exist?(COUNCIL_PATH) ? (Master.load_yaml(COUNCIL_PATH) || {}) : {}
        data.dig("presets", "sound_critique") || {}
      end

      def build_panel(preset)
        all = Personas.load
        names = Array(preset["panel"] || SOUND_PANEL).map(&:downcase)
        panel = all.select { |persona| names.include?(persona.name.downcase) }
        panel.empty? ? Personas::DEFAULTS : panel
      end

      def build_payload(preset)
        files = Array(preset["files"]).any? ? preset["files"] : default_files
        combined = files.filter_map do |relative_path|
          path = File.join(Master::ROOT, relative_path)
          next unless File.exist?(path)

          raw = File.read(path, encoding: "utf-8")
          raw = raw.byteslice(0, MAX_FILE_BYTES) + "\n... [truncated]" if raw.bytesize > MAX_FILE_BYTES
          "file: #{relative_path}\n#{raw}"
        end.join("\n\n")

        { combined: combined, files: files }
      end

      def default_files
        %w[
          web/public/chat.js
          web/public/face.js
          web/public/visual_bridge.js
          web/app/views/chat/index.html.erb
          lib/voice/speech.rb
          lib/voice/dilla.rb
          lib/voice/production_dna.rb
        ]
      end

      def sound_context
        <<~CTX
          Review MASTER as an interactive AI agent with visual motion, chat streaming, and voice/audio affordances.
          Treat sound design as product behavior, not decoration.
          Evaluate sonic hierarchy, timing, mix role, accessibility, graceful failure, implementation size, and TTS quality.
          #{Deliberation.quality_brief(:sound)}
          #{sonitex_brief}
          #{dilla_brief}
          #{tts_lofi_brief}
          Return shippable, reversible fixes, not vague mood boards.
        CTX
      end

      def sonitex_brief
        "Lo-fi chain: prefer cumulative subtle degradation; document any SoX/ffmpeg gaps as opt-in."
      end

      def dilla_brief
        if defined?(Master::Voice::Dilla)
          Master::Voice::Dilla.brief
        elsif defined?(Master::Voice::ProductionDna)
          Master::Voice::ProductionDna.brief
        else
          "Production DNA unavailable; keep timing human, restrained, and non-quantized when musical."
        end
      rescue StandardError => e
        "Dilla production profile failed to load: #{e.message}."
      end

      def tts_lofi_brief
        "TTS policy: edge-tts primary (ms-MY-OsmanNeural via bin/tts-worker); espeak hard fallback; clean audio default; lofi effects opt-in only."
      end

      def sound_constraints
        [
          "no autoplay without user intent",
          "must expose mute or silence path",
          "must not mask speech or screen-reader output",
          "must degrade when AudioContext or media playback fails",
          "prefer tiny generated tones or short assets over heavy dependencies",
          "preserve existing visual identity",
          "use Ruby QualityFramework sound rules from Deliberation",
          "when lo-fi processing is proposed, document it as opt-in and shell out via a dedicated worker, not inline",
          "when Dilla-style timing is proposed, call Master::Voice::Dilla for swing, nudge, chord, and preset data",
          "TTS backend is edge-tts via bin/tts-worker; espeak is the only fallback; no other TTS backends"
        ]
      end

      def cherry_pick(feedback, final_ideas)
        feedback_text = feedback.map { |entry| entry[:feedback].to_s }.join("\n")
        final_ideas.to_s.lines.map(&:strip).reject(&:empty?).sort_by do |line|
          -text_overlap(line, feedback_text)
        end.first(12)
      end

      def text_overlap(a, b)
        left = a.downcase.scan(/\w+/).to_set
        right = b.downcase.scan(/\w+/).to_set
        return 0.0 if left.empty? || right.empty?
        (left & right).size.to_f / left.size
      end
    end
  end
  end
end