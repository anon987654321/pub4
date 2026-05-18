# frozen_string_literal: true

module Master
  module Judge
  module Council
    class UiCritique
      COUNCIL_PATH = File.join(Master::ROOT, "data", "council.yml").freeze
      DESIGN_RULES_PATH = File.join(Master::ROOT, "data", "design_rules.yml").freeze
      WEB_ROOT     = File.join(Master::ROOT, "web").freeze
      MAX_FILE_BYTES = 32_768

      UI_PANEL = %w[
        Architect Graphic\ Designer Web\ Designer Electronic\ Music\ Producer
        Hip-Hop\ Producer Google\ CSS\ Engineer NNGroup\ UX\ Researcher
        Accessibility User\ Advocate Layperson Skeptic
      ].freeze

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus   = event_bus
      end

      def run
        preset  = load_preset
        panel   = build_panel(preset)
        payload = build_payload(preset)
        @bus&.publish(:ui_critique_start, files: payload.keys, personas: panel.map(&:name))

        delib = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
        result = delib.review(payload[:combined], context: ui_context)
        return result unless result.ok?

        feedback = result.value!
        ideate   = Ideation.new(agent: @agent, event_bus: @bus)
        ideas    = ideate.ideate(
          "Generate concrete multi-solution improvements for this web UI. " \
          "Be brutally honest. Produce 3 distinct solution directions per issue found.",
          constraints: design_constraints,
          cycles: (preset.dig("cycles") || 1).to_i
        )

        cherry   = cherry_pick(feedback, ideas)
        @bus&.publish(:ui_critique_done, cherry_picks: cherry.size)
        Master::Result.ok({ feedback: feedback, ideas: ideas, cherry_picks: cherry })
      end

      private

      def load_preset
        data = File.exist?(COUNCIL_PATH) ? (Master.load_yaml(COUNCIL_PATH) || {}) : {}
        data.dig("presets", "ui_critique") || {}
      end

      def build_panel(preset)
        all  = Personas.load
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
          Critique the CSS, JS, HTML semantics, animation approach, typography, layout, hierarchy, accessibility, and data-ink economy.
          Use the codified design rules below as measurable guidance, not rigid dogma.
          #{design_rules_context}
          Be brutally honest. Maximum scrutiny. Return shippable fixes.
        CTX
      end

      def design_rules_context
        rules = File.exist?(DESIGN_RULES_PATH) ? Master.load_yaml(DESIGN_RULES_PATH) : {}
        return "Design rules: unavailable." if rules.empty?

        typography = rules.fetch("typography", {})
        layout = rules.fetch("layout", {})
        visual = rules.fetch("visual_design", {})
        data = rules.fetch("data_visualization", {})
        <<~RULES
          Design rules:
          - line length #{typography.dig("line_length", "min_ch")}-#{typography.dig("line_length", "max_ch")}ch, ideal #{typography.dig("line_length", "ideal_ch")}ch
          - body line-height #{typography.dig("line_height", "body_min")}-#{typography.dig("line_height", "body_max")}; raise to #{typography.dig("line_height", "long_line_min")} when lines exceed #{typography.dig("line_height", "long_line_threshold_ch")}ch
          - all-caps tracking #{typography.dig("letter_spacing", "all_caps_min_em")}-#{typography.dig("letter_spacing", "all_caps_max_em")}em; no letter-spaced lowercase prose
          - hierarchy needs at least #{typography.dig("hierarchy", "min_size_ratio_between_levels")}x size contrast or #{typography.dig("hierarchy", "min_weight_delta")} font-weight delta
          - max #{typography.dig("hierarchy", "max_font_families")} families, #{typography.dig("hierarchy", "max_font_weights")} weights, #{typography.dig("hierarchy", "max_font_sizes")} sizes
          - contrast #{typography.dig("accessibility", "normal_text_contrast")}:1 normal, #{typography.dig("accessibility", "large_text_contrast")}:1 large
          - grid #{layout.dig("grid", "columns")} columns, #{layout.dig("grid", "base_unit_px")}px base spacing, touch target #{layout.dig("touch", "target_min_px")}px minimum
          - center-aligned prose must stay under #{layout.dig("alignment", "center_text_max_lines")} lines
          - arbitrary decoration rejected: #{visual.dig("semantics", "reject_arbitrary_decoration")}
          - data-ink target #{data["data_ink_ratio_target"]}; remove chartjunk unless it carries information
        RULES
      rescue StandardError => e
        "Design rules failed to load: #{e.message}."
      end

      def design_constraints
        [
          "must not break existing HTML semantics",
          "must preserve intentional CSS measurements unless a codified design rule is violated",
          "animations must respect prefers-reduced-motion",
          "solutions must be implementable without a build step",
          "use typography, layout, visual_design, and data_visualization rules from data/design_rules.yml",
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