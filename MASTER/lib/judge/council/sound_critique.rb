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
        ideation = Ideation.new(agent: @agent, event_bus: @bus)
        ideas = ideation.ideate(
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
        ]
      end

      def sound_context
        <<~CTX
          Review MASTER as an interactive AI agent with visual motion, chat streaming, and voice/audio affordances.
          Treat sound design as product behavior, not decoration.
          Evaluate:
          - sonic hierarchy: what should be foreground, background, or silent
          - timing: attack, decay, pauses, streaming cadence, notification rhythm
          - mix role: whether sounds sit under speech, reinforce state, or distract
          - accessibility: mute, reduced motion, no autoplay surprise, screen-reader coexistence
          - implementation: small browser-native assets, no build step, graceful failure
          Return shippable fixes, not vague mood boards.
        CTX
      end

      def sound_constraints
        [
          "no autoplay without user intent",
          "must expose mute or silence path",
          "must not mask speech or screen-reader output",
          "must degrade when AudioContext or media playback fails",
          "prefer tiny generated tones or short assets over heavy dependencies",
          "preserve existing visual identity"
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