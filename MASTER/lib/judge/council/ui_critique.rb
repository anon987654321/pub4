# frozen_string_literal: true

module Master
  module Judge
  module Council
    class UiCritique
      COUNCIL_PATH = File.join(Master::ROOT, "data", "council.yml").freeze
      WEB_ROOT = File.join(Master::ROOT, "web").freeze
      MAX_FILE_BYTES = 32_768

      UI_PANEL = %w[
        Architect Graphic\ Designer Web\ Designer Electronic\ Music\ Producer
        Hip-Hop\ Producer Google\ CSS\ Engineer NNGroup\ UX\ Researcher
        Accessibility User\ Advocate Layperson Skeptic
      ].freeze

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus = event_bus
      end

      def run
        preset = load_preset
        panel = build_panel(preset)
        payload = build_payload(preset)
        @bus&.publish(:ui_critique_start, files: payload[:files], personas: panel.map(&:name))

        delib = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
        result = delib.review(payload[:combined], context: ui_context)
        return result unless result.ok?

        feedback = result.value!
        ideas = Ideation.new(agent: @agent, event_bus: @bus).ideate(
          "Generate concrete multi-solution improvements for this web UI. Produce 3 distinct solution directions per issue found.",
          constraints: design_constraints,
          cycles: (preset.dig("cycles") || 1).to_i
        )

        cherry = cherry_pick(feedback, ideas)
        @bus&.publish(:ui_critique_done, cherry_picks: cherry.size)
        Master::Result.ok({ feedback: feedback, ideas: ideas, cherry_picks: cherry })
      end

      private

      def load_preset
        data = File.exist?(COUNCIL_PATH) ? (Master.load_yaml(COUNCIL_PATH) || {}) : {}
        data.dig("presets", "ui_critique") || {}
      end

      def build_panel(preset)
        all = Personas.load
        names = Array(preset["panel"]).map(&:downcase)
        return all if names.empty?

        all.select { |p| names.include?(p.name.downcase) }
           .tap { |panel| panel.replace(Personas::DEFAULTS) if panel.empty? }
      end

      def build_payload(preset)
        files = Array(preset["files"]).any? ? preset["files"] : default_files
        combined = files.filter_map do |rel|
          path = File.join(Master::ROOT, rel)
          next unless File.exist?(path)

          raw = File.read(path, encoding: "utf-8")
          raw = raw.byteslice(0, MAX_FILE_BYTES) + "\n... [truncated]" if raw.bytesize > MAX_FILE_BYTES
          "file: #{rel}\n#{raw}"
        end.join("\n\n")

        { combined: combined, files: files }
      end

      def default_files
        %w[
          web/public/face.css
          web/public/face.js
          web/public/chat.js
          web/app/views/chat/index.html.erb
          lib/design/platform_profiles.rb
        ]
      end

      def ui_context
        <<~CTX
          This is the MASTER constitutional AI agent web UI. Design intent:
          - Full-screen canvas particle face (WebGL-free, 2D Canvas API)
          - Particles form 3D face shape, morph between poses like a swarm
          - Black background, white/grey/dark-red particles, 1px only
          - Chat panel slides in from right, oh-my-zsh style prompt
          - Edge-tts Osman voice, server-side, AudioContext playback
          - Visitor access (no token), authenticated (token) tiers
          Critique CSS, JS, HTML semantics, animation, typography, layout, hierarchy, accessibility, and data-ink economy.
          #{Deliberation.quality_brief(:design)}
          #{platform_profile_brief}
          Return shippable, reversible fixes with measurable reasons.
        CTX
      end

      def platform_profile_brief
        if defined?(Master::Design::PlatformProfiles)
          [
            Master::Design::PlatformProfiles.brief(:brutal_minimal),
            Master::Design::PlatformProfiles.brief(:medium),
            Master::Design::PlatformProfiles.brief(:new_yorker)
          ].join("\n")
        else
          "Platform design profiles unavailable; default to content-first measurable critique."
        end
      rescue StandardError => e
        "Platform profile policy failed to load: #{e.message}."
      end

      def design_constraints
        [
          "must not break existing HTML semantics",
          "must preserve intentional CSS measurements unless a measurable rule is violated",
          "animations must respect prefers-reduced-motion",
          "solutions must be implementable without a build step",
          "use Ruby QualityFramework design rules from Deliberation",
          "use Master::Design::PlatformProfiles for content-first and profile-specific critique",
          "distinguish measurable violations from subjective taste"
        ]
      end

      def cherry_pick(feedback, ideas)
        texts = feedback.map { |f| f[:feedback].to_s }
        idea_lines = ideas.to_s.lines.map(&:strip).reject(&:empty?)
        scored = idea_lines.map do |line|
          score = texts.sum { |t| text_overlap(line, t) }
          [line, score]
        end
        scored.sort_by { |_, s| -s }.first(12).map(&:first)
      end

      def text_overlap(a, b)
        wa = a.downcase.scan(/\w+/).to_set
        wb = b.downcase.scan(/\w+/).to_set
        (wa & wb).size.to_f / ([wa.size, wb.size, 1].max)
      end
    end
  end
  end
end