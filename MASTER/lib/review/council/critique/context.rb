# frozen_string_literal: true

module Master
  module Review
    module Council
      class Critique
        # The briefing the panel reads before it critiques: what surface this
        # is, what to judge it on, and which house design/sound briefs apply.
        #
        # This is prose for the model, not orchestration, and it was four
        # near-identical predicate methods plus two brief loaders inside
        # Critique. Keyed by preset_key so adding a mode is a table entry here
        # rather than another `return … if @mode[:preset_key] == …` line.
        class Context
          DOMAINS = {
            "ui_critique" => <<~CTX,
              This is the MASTER constitutional AI agent web UI. Design intent:
              - Full-screen canvas particle face (WebGL-free, 2D Canvas API)
              - Particles form 3D face shape, morph between poses like a swarm
              - Black background, white/grey/dark-red particles, 1px only
              - Chat panel slides in from right, oh-my-zsh style prompt
              - Edge-tts Osman voice, server-side, AudioContext playback
              - Visitor access (no token), authenticated (token) tiers
              Critique CSS, JS, HTML semantics, animation, typography, layout, hierarchy, accessibility, and data-ink economy.
            CTX
            "sound_critique" => <<~CTX,
              Review MASTER as an interactive AI agent with visual motion, chat streaming, and voice/audio affordances.
              Treat sound design as product behavior, not decoration.
              Evaluate sonic hierarchy, timing, mix role, accessibility, graceful failure, implementation size, and TTS quality.
            CTX
            "dilla_critique" => <<~CTX,
              Review the Dilla audio engine (STUDIO/dilla) and any measured mix metrics.
              Goal: best possible pad-forward single-style render.
              Evaluate spectral hierarchy (pad vs sub), HF air, presence, groove density,
              headroom/crest, curated harmony, and platform loudness.
              Process: each persona critiques → multi-solution ideation per issue → cherry-pick best.
              Implementation must stay inside existing engine knobs and MASTER commands — no parallel crit stack.
            CTX
            "general_critique" => <<~CTX,
              Reviewing whatever MASTER just scanned or fixed -- not a fixed product
              surface, so judge each file on its own conventions rather than a
              house style. Process: each persona critiques → multi-solution
              ideation per issue → cherry-pick best.
            CTX
          }.freeze

          DILLA_BRIEF_MODES = %w[sound_critique dilla_critique].freeze

          def initialize(preset_key:, quality_kind:)
            @preset_key = preset_key
            @quality_kind = quality_kind
          end

          def to_s
            [DOMAINS[@preset_key], Deliberation.quality_brief(@quality_kind), briefs].compact.join("\n")
          end

          private

          def briefs
            return platform_profile_brief if @preset_key == "ui_critique"

            Master::Voice::Dilla.council_brief if DILLA_BRIEF_MODES.include?(@preset_key)
          end

          def platform_profile_brief
            unless defined?(Master::Design::PlatformProfiles)
              return "Platform design profiles unavailable; default to content-first measurable critique."
            end

            %i[brutal_minimal medium new_yorker]
              .map { |profile| Master::Design::PlatformProfiles.brief(profile) }
              .join("\n")
          rescue StandardError => e
            "Platform profile policy failed to load: #{e.message}."
          end
        end
      end
    end
  end
end
