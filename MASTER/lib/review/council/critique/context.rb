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

          # Which principle clusters each mode's panel is briefed on.
          #
          # The council convened with its persona names and the diff, and nothing
          # else: Critique loaded council.yml and no other data file, so the
          # Typographer had no typography principles and the Architect had no
          # architecture ones. principle_map.yml held 135 of them the panel never
          # saw, and the 137 recovered from master.yml are exactly the kind a
          # scanner cannot check and a judge can — which is why they were dropped
          # when the only consumer left was a regex.
          PRINCIPLE_CLUSTERS = {
            "ui_critique" => %w[visual_design ux_laws typography aesthetic architecture japanese_aesthetics],
            # Not `aesthetic` — that tag is where the visual principles live, and
            # briefing a sound panel on "equal visual weight distribution" is
            # noise. The Japanese register is the one that carries timing and
            # restraint (jo_ha_kyu is literally a rhythm).
            "sound_critique" => %w[japanese_aesthetics],
            "dilla_critique" => %w[japanese_aesthetics],
            "general_critique" => %w[refactoring clean_code engineering structure errors security],
          }.freeze

          # A briefing, not a dump. The whole map is 272 entries; past this the
          # panel is reading a dictionary instead of judging a diff.
          PRINCIPLE_LIMIT = 45

          def initialize(preset_key:, quality_kind:)
            @preset_key = preset_key
            @quality_kind = quality_kind
          end

          def to_s
            [
              DOMAINS[@preset_key],
              Deliberation.quality_brief(@quality_kind),
              briefs,
              principle_brief,
            ].compact.join("\n")
          end

          private

          def briefs
            return platform_profile_brief if @preset_key == "ui_critique"

            Master::Voice::Dilla.council_brief if DILLA_BRIEF_MODES.include?(@preset_key)
          end

          # House principles for this panel, as `id — meaning` lines. Silent when
          # the map cannot load: a missing briefing degrades the critique, and
          # failing the whole council over it would be worse.
          def principle_brief
            clusters = PRINCIPLE_CLUSTERS[@preset_key]
            all = clusters ? principles_in(clusters) : []
            return if all.empty?

            lines = sample(all, clusters).map { |entry| "- #{entry.id} — #{entry.meaning.to_s.strip}" }
            <<~BRIEF
              House principles for this panel (#{lines.size} of #{all.size}), from data/principle_map.yml.
              Cite the ones a change violates or satisfies by name; do not treat the list as a checklist to walk.
              #{lines.join("\n")}
            BRIEF
          rescue StandardError => e
            "House principles unavailable (#{e.class}); critique on the surface's own conventions."
          end

          def principles_in(clusters)
            Master::Ground::Map::Principle.load.principles.values.select { |entry| (entry.tags & clusters).any? }
          end

          # Round-robin across the clusters, not the first N alphabetically.
          # Sorting and truncating gave the UI panel a..c and cut `yugen` and
          # `truth_to_materials` off the end — a cap that silently decides which
          # half of the alphabet the council believes in. Deterministic, because
          # a briefing that changes between runs makes two critiques
          # incomparable.
          def sample(entries, clusters)
            buckets = clusters.map { |cluster| entries.select { |e| e.tags.include?(cluster) }.sort_by(&:id) }
            depth = buckets.map(&:size).max.to_i
            (0...depth).flat_map { |i| buckets.filter_map { |bucket| bucket[i] } }
                       .uniq(&:id).first(PRINCIPLE_LIMIT).sort_by(&:id)
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
