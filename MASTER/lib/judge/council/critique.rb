# frozen_string_literal: true

module Master
  module Judge
  module Council
    # Mode-dispatched council critique. Replaces UiCritique + SoundCritique.
    # Each mode is a config hash: preset key, default files/panel, context
    # briefs, constraints, ideation prompt, byte cap, event names.
    class Critique
      MODES = {
        ui: {
          preset_key: "ui_critique",
          max_bytes:  32_768,
          panel:      nil,
          files: %w[
            web/public/face.css web/public/face.js web/public/chat.js
            web/app/views/chat/index.html.erb lib/design/platform_profiles.rb
          ],
          quality_kind:    :design,
          ideation_prompt: "Generate concrete multi-solution improvements for this web UI. " \
                           "Produce 3 distinct solution directions per issue found.",
          cycles_default:  1,
          start_event:     :ui_critique_start,
          done_event:      :ui_critique_done,
          constraints: [
            "must not break existing HTML semantics",
            "must preserve intentional CSS measurements unless a measurable rule is violated",
            "animations must respect prefers-reduced-motion",
            "solutions must be implementable without a build step",
            "use Ruby QualityFramework design rules from Deliberation",
            "use Master::Design::PlatformProfiles for content-first and profile-specific critique",
            "distinguish measurable violations from subjective taste"
          ]
        },
        sound: {
          preset_key: "sound_critique",
          max_bytes:  24_576,
          panel:      %w[
            Electronic\ Music\ Producer Hip-Hop\ Producer User\ Advocate
            Accessibility Layperson Skeptic
          ],
          files: %w[
            web/public/chat.js web/public/face.js web/public/visual_bridge.js
            web/app/views/chat/index.html.erb lib/voice/speech.rb lib/voice/dilla.rb
            lib/voice/production_dna.rb
          ],
          quality_kind:    :sound,
          ideation_prompt: "Generate concrete improvements for MASTER sound design, voice " \
                           "playback, sonic timing, and audio feedback.",
          cycles_default:  2,
          start_event:     :sound_critique_start,
          done_event:      :sound_critique_done,
          constraints: [
            "no autoplay without user intent",
            "must expose mute or silence path",
            "must not mask speech or screen-reader output",
            "must degrade when AudioContext or media playback fails",
            "prefer tiny generated tones or short assets over heavy dependencies",
            "preserve existing visual identity",
            "use Ruby QualityFramework sound rules from Deliberation",
            "when Dilla-style timing is proposed, call Master::Voice::Dilla for swing, nudge, chord, and preset data",
          ]
        }
      }.freeze

      def initialize(mode:, agent:, event_bus: nil)
        @mode  = MODES.fetch(mode) { raise ArgumentError, "unknown critique mode: #{mode}" }
        @agent = agent
        @bus   = event_bus
      end

      def run
        preset  = load_preset
        panel   = build_panel(preset)
        payload = build_payload(preset)
        @bus&.publish(@mode[:start_event], files: payload[:files], personas: panel.map(&:name))

        delib  = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
        result = delib.review(payload[:combined], context: build_context)
        return result unless result.ok?

        ideation_result = Ideation.new(agent: @agent, event_bus: @bus).ideate(
          @mode[:ideation_prompt],
          constraints: @mode[:constraints],
          cycles:      (preset["cycles"] || @mode[:cycles_default]).to_i
        )

        feedback = result.value!
        cherry   = cherry_pick_from(feedback, ideation_result)
        @bus&.publish(@mode[:done_event], cherry_picks: cherry.size)
        Master::Result.ok({ feedback: feedback, ideas: ideation_value(ideation_result), cherry_picks: cherry })
      end

      private

      def load_preset
        return {} unless File.exist?(Master::COUNCIL_PATH)
        data = Master.load_yaml(Master::COUNCIL_PATH) || {}
        data.dig("presets", @mode[:preset_key]) || {}
      end

      def build_panel(preset)
        all   = Personas.load
        names = Array(preset["panel"] || @mode[:panel]).map(&:downcase)
        return all if names.empty?
        picked = all.select { |p| names.include?(p.name.downcase) }
        picked.empty? ? Personas::DEFAULTS : picked
      end

      def build_payload(preset)
        files    = Array(preset["files"]).any? ? preset["files"] : @mode[:files]
        combined = files.filter_map { |rel| read_truncated(rel) }.join("\n\n")
        { combined: combined, files: files }
      end

      def read_truncated(rel)
        path = File.join(Master::ROOT, rel)
        return nil unless File.exist?(path)
        raw = File.read(path, encoding: "utf-8")
        raw = raw.byteslice(0, @mode[:max_bytes]) + "\n... [truncated]" if raw.bytesize > @mode[:max_bytes]
        "file: #{rel}\n#{raw}"
      end

      def build_context
        [domain_context, Deliberation.quality_brief(@mode[:quality_kind]), domain_briefs]
          .compact.join("\n")
      end

      def domain_context
        return ui_domain_context if @mode[:preset_key] == "ui_critique"
        sound_domain_context
      end

      def ui_domain_context
        <<~CTX
          This is the MASTER constitutional AI agent web UI. Design intent:
          - Full-screen canvas particle face (WebGL-free, 2D Canvas API)
          - Particles form 3D face shape, morph between poses like a swarm
          - Black background, white/grey/dark-red particles, 1px only
          - Chat panel slides in from right, oh-my-zsh style prompt
          - Edge-tts Osman voice, server-side, AudioContext playback
          - Visitor access (no token), authenticated (token) tiers
          Critique CSS, JS, HTML semantics, animation, typography, layout, hierarchy, accessibility, and data-ink economy.
        CTX
      end

      def sound_domain_context
        <<~CTX
          Review MASTER as an interactive AI agent with visual motion, chat streaming, and voice/audio affordances.
          Treat sound design as product behavior, not decoration.
          Evaluate sonic hierarchy, timing, mix role, accessibility, graceful failure, implementation size, and TTS quality.
        CTX
      end

      def domain_briefs
        return platform_profile_brief if @mode[:preset_key] == "ui_critique"
        [dilla_brief].join("\n")
      end

      def platform_profile_brief
        return "Platform design profiles unavailable; default to content-first measurable critique." \
          unless defined?(Master::Design::PlatformProfiles)
        %i[brutal_minimal medium new_yorker].map { |k| Master::Design::PlatformProfiles.brief(k) }.join("\n")
      rescue StandardError => e
        "Platform profile policy failed to load: #{e.message}."
      end

      def dilla_brief
        return Master::Voice::Dilla.brief         if defined?(Master::Voice::Dilla)
        return Master::Voice::ProductionDna.brief if defined?(Master::Voice::ProductionDna)
        "Production DNA unavailable; keep timing human, restrained, and non-quantized when musical."
      rescue StandardError => e
        "Dilla production profile failed to load: #{e.message}."
      end

      def ideation_value(ir)
        ir.respond_to?(:err?) && ir.err? ? "" : (ir.respond_to?(:value) ? ir.value : ir)
      end

      def cherry_pick_from(feedback, ideation_result)
        text = if ideation_result.respond_to?(:value)
                 ideation_result.value.is_a?(Hash) ? ideation_result.value.fetch(:final, "") : ideation_result.value.to_s
               else
                 ideation_result.to_s
               end
        cherry_pick(feedback, text)
      end

      def cherry_pick(feedback, ideas_text)
        feedback_text = feedback.map { |f| f[:feedback].to_s }.join("\n")
        lines = ideas_text.to_s.lines.map(&:strip).reject(&:empty?)
        lines.sort_by { |line| -text_overlap(line, feedback_text) }.first(12)
      end

      def text_overlap(a, b)
        wa = a.downcase.scan(/\w+/).to_set
        wb = b.downcase.scan(/\w+/).to_set
        return 0.0 if wa.empty? || wb.empty?
        (wa & wb).size.to_f / wa.size
      end
    end
  end
  end
end
