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
                web/app/views/chat/index.html.erb lib/design.rb
              ],
              quality_kind: :design,
              ideation_prompt: "Generate concrete multi-solution improvements for this web UI. " \
                               "For each issue, propose materially different repair directions before selecting the strongest one.",
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
                "treat the attached rendered screenshot as the visual ground truth",
                "format every actionable UI issue as surface=<id> viewport=<name> selector=<stable-selector> or surface=<id> viewport=<name> visible text=\"<exact visible text>\"",
                "start each actionable UI issue with its issue number so ideation can preserve the council anchor",
                "use first-screen composition facts as evidence, but do not confuse a metric threshold with visual quality",
                "when the render has no actionable defect or evidence-backed improvement, state VISUAL_CLEAN explicitly",
                "judge typography, hierarchy, spacing, alignment, density, grouping and composition in the render, not only in CSS",
                "establish a purpose-led aesthetic direction before suggesting changes; preserve one memorable element instead of making every region compete",
                "treat genericity signals such as gradients, rounded-card systems, shadow-card systems, pill overload and centered hero patterns as review prompts, not automatic violations",
                "for a substantial redesign, compare three structurally different composition directions before choosing a repair: conservative evolution, structural reinterpretation, bold alternative",
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
                "do not invent a second critique system inside MASTER/tools/dilla — perfect via MASTER commands",
              ],
            },
            dilla: {
              preset_key: "dilla_critique",
              max_bytes: 36_864,
              panel: [
                "Electronic Music Producer", "Sound Engineer", "Label Executive", "Graphic Designer",
                "Web Designer", "Sound Designer", "Organ Composer", "Hip-Hop Producer", "Skeptic"
              ],
              # dilla.rb is the entry script and little else since the engine was
              # split into lib/engine/. It stays because the panel needs to see
              # what the CLI offers, but max_bytes means a list is a budget: name
              # the parts that decide how a render SOUNDS, or the panel critiques
              # the boot sequence. Before the split this read the first 36 KB of a
              # 1.37 MB file — the patch catalogue, and nothing downstream of it.
              files: %w[
                tools/dilla/dilla.rb
                tools/dilla/lib/engine/master_chain.rb
                tools/dilla/lib/engine/bus_filters.rb
                tools/dilla/lib/engine/drum_bus_filter.rb
                tools/dilla/lib/engine/groove_timing.rb
                tools/dilla/lib/listen.rb
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
                "surgical ENV/mix changes only — no second crit engine inside MASTER/tools/dilla",
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
                "prefer evidence-backed micro-smell correction, simplification, clearer naming, and duplication removal over redesign",
                "for every actionable issue or improvement, name the repository-relative file and stable line or symbol; unanchored observations are not repairs",
                "a clean deterministic scan means no registered detector fired, not that the artifact is beyond improvement",
              ],
            },
          }.freeze
        end
      end
    end
  end
end
