# frozen_string_literal: true

module Master
  module Review
    module Council
      class Critique
        # The mode table: which files a critique reads, which personas sit on
        # the panel, and the constraints their solutions must satisfy.
        #
        # This is configuration, not behaviour, and at 107 lines it was a third
        # of Critique's body — the reason the class read as a god class. Lifted
        # here so Critique is the orchestration and this is the data it runs on.
        # `Critique::MODES` still resolves; it aliases TABLE.
        module Modes
          TABLE = {
            ui: {
              preset_key: "ui_critique",
              max_bytes: 32_768,
              panel: nil,
              files: %w[
                web/public/face.css web/public/face.js web/public/chat.js
                web/app/views/chat/index.html.erb lib/design/platform_profiles.rb
              ],
              quality_kind: :design,
              ideation_prompt: "Generate concrete multi-solution improvements for this web UI. " \
                               "Produce 3 distinct solution directions per issue found.",
              cycles_default: 1,
              start_event: :ui_critique_start,
              done_event: :ui_critique_done,
              constraints: [
                "must not break existing HTML semantics",
                "must preserve intentional CSS measurements unless we violate a measurable rule",
                "animations must respect prefers-reduced-motion",
                "solutions must be implementable without a build step",
                "use Ruby QualityFramework design rules from Deliberation",
                "use Master::Design::PlatformProfiles for content-first and profile-specific critique",
                "distinguish measurable violations from subjective taste",
              ],
            },
            sound: {
              preset_key: "sound_critique",
              max_bytes: 24_576,
              panel: [
                "Electronic Music Producer", "Hip-Hop Producer", "Sound Designer", "Sound Engineer",
                "User Advocate", "Accessibility", "Layperson", "Skeptic"
              ],
              files: %w[
                web/public/chat.js web/public/face.js web/public/visual_bridge.js
                web/app/views/chat/index.html.erb lib/voice/speech.rb lib/voice/dilla.rb
                lib/voice/production_dna.rb
              ],
              quality_kind: :sound,
              ideation_prompt: "For each issue, propose 3 concrete solutions, then cherry-pick the best " \
                               "for MASTER sound design, voice playback, sonic timing, and audio feedback.",
              cycles_default: 2,
              start_event: :sound_critique_start,
              done_event: :sound_critique_done,
              include_mix_metrics: true,
              constraints: [
                "no autoplay without user intent",
                "must expose mute or silence path",
                "must not mask speech or screen-reader output",
                "must degrade when AudioContext or media playback fails",
                "prefer tiny generated tones or short assets over heavy dependencies",
                "preserve existing visual identity",
                "use Ruby QualityFramework sound rules from Deliberation",
                "when proposing Dilla-style timing, call Master::Voice::Dilla for swing, nudge, chord, and preset data",
                "do not invent a second critique system inside STUDIO/dilla — perfect via MASTER commands",
              ],
            },
            dilla: {
              preset_key: "dilla_critique",
              max_bytes: 36_864,
              panel: [
                "Electronic Music Producer", "Sound Engineer", "Label Executive", "Graphic Designer",
                "Web Designer", "Sound Designer", "Organ Composer", "Hip-Hop Producer", "Skeptic"
              ],
              files: %w[
                ../STUDIO/dilla/dilla.rb ../STUDIO/dilla/lib/master_heuristics.rb
                lib/voice/dilla.rb lib/voice/production_dna.rb
                lib/io/analog_capabilities.rb
              ],
              quality_kind: :sound,
              ideation_prompt: "Review the Dilla engine and measured mix. For EACH problem the panel " \
                               "raises, generate 3 distinct solutions (ENV knobs, bus EQ, groove density, " \
                               "harmony locks — no producer-name modes). Then cherry-pick the single best " \
                               "fix per problem that preserves pad-forward single-style dilla character.",
              cycles_default: 2,
              start_event: :sound_critique_start,
              done_event: :sound_critique_done,
              include_mix_metrics: true,
              constraints: [
                "single style only (RENDER_MODE=dilla); no multi-producer mode tables",
                "do not name producers in code or ENV keys",
                "pad bed must remain readable; kit air may open but no noise-wall vinyl fix",
                "prefer existing FLAG_ENV / DILLA_STYLE_DEFAULTS knobs over new files",
                "use Master::Voice::Dilla and ProductionDna for timing/DNA; use MixMetrics for evidence",
                "multi-solution then cherry-pick is mandatory (QualityFramework general rule)",
                "surgical ENV/mix changes only — no second crit engine inside STUDIO/dilla",
              ],
            },
            # General: whatever MASTER is currently processing (usually the
            # path /scan and /fix just touched), not a fixed product surface.
            # panel: nil -> build_panel falls back to every persona, since a
            # scanned path could be Ruby, JS, CSS, or YAML.
            general: {
              preset_key: "general_critique",
              max_bytes: 32_768,
              panel: nil,
              files: [].freeze,
              quality_kind: :general,
              ideation_prompt: "For each issue, propose 3 concrete solutions, then cherry-pick the " \
                               "single best fix per problem -- prefer the smallest change that actually " \
                               "resolves it over a rewrite.",
              cycles_default: 1,
              start_event: :general_critique_start,
              done_event: :general_critique_done,
              constraints: [
                "surgical, minimal changes that fit existing conventions in the file",
                "distinguish measurable violations from subjective taste",
                "no speculative abstractions or unrequested refactors",
              ],
            },
          }.freeze
        end
      end
    end
  end
end
