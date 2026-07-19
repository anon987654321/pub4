# frozen_string_literal: true

module Master
  module Review
    module Council
      # Mode-dispatched council critique. Replaces UiCritique + SoundCritique.
      class Critique
        MODES = {
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
            panel: %w[
              Electronic\ Music\ Producer Hip-Hop\ Producer Sound\ Designer
              Sound\ Engineer User\ Advocate Accessibility Layperson Skeptic
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
              "do not invent a second critique system inside tools/dilla — perfect via MASTER commands",
            ],
          },
          dilla: {
            preset_key: "dilla_critique",
            max_bytes: 36_864,
            panel: %w[
              Electronic\ Music\ Producer Sound\ Engineer Label\ Executive
              Graphic\ Designer Web\ Designer Sound\ Designer Organ\ Composer
              Hip-Hop\ Producer Skeptic
            ],
            files: %w[
              tools/dilla/dilla.rb tools/dilla/lib/master_heuristics.rb
              tools/dilla.rb lib/voice/dilla.rb lib/voice/production_dna.rb
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
              "surgical ENV/mix changes only — no second crit engine inside tools/dilla",
            ],
          },
        }.freeze

        def initialize(mode:, agent:, event_bus: nil, audio_path: nil)
          @mode = MODES.fetch(mode) { raise ArgumentError, "unknown critique mode: #{mode}" }
          @agent = agent
          @bus = event_bus
          @audio_path = audio_path
        end

        def run
          preset = load_preset
          panel = build_panel(preset)
          payload = build_payload(preset)
          @bus&.publish(@mode[:start_event], files: payload[:files], personas: panel.map(&:name))

          delib = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
          result = delib.review(payload[:combined], context: build_context)
          return result unless result.ok?

          ideation_result = Ideation.new(agent: @agent, event_bus: @bus).ideate(
            @mode[:ideation_prompt],
            constraints: @mode[:constraints],
            cycles: (preset["cycles"] || @mode[:cycles_default]).to_i
          )

          feedback = result.value!
          cherry = cherry_pick_from(feedback, ideation_result)
          @bus&.publish(@mode[:done_event], cherry_picks: cherry.size)
          Master::Result.ok({
            feedback: feedback,
            ideas: ideation_value(ideation_result),
            cherry_picks: cherry,
            metrics: payload[:metrics],
            mode: @mode[:preset_key],
          })
        end

        private

        def load_preset
          return {} unless File.exist?(Master::COUNCIL_PATH)
          data = Master.load_yaml(Master::COUNCIL_PATH) || {}
          data.dig("presets", @mode[:preset_key]) || {}
        end

        def build_panel(preset)
          all = Personas.load
          names = Array(preset["panel"] || @mode[:panel]).map(&:downcase)
          return all if names.empty?

          panel = all.select { |persona| names.include?(persona.name.downcase) }
          panel.empty? ? Personas::DEFAULTS : panel
        end

        def build_payload(preset)
          files = Array(preset["files"]).any? ? preset["files"] : @mode[:files]
          combined = files.filter_map { |rel| read_truncated(rel) }.join("\n\n")
          metrics = mix_metrics_block if @mode[:include_mix_metrics]
          combined = [metrics, combined].compact.join("\n\n") if metrics
          { combined: combined, files: files, metrics: metrics }
        end

        def mix_metrics_block
          require_relative "../../voice/mix_metrics"
          path = @audio_path || Master::Voice::MixMetrics.first_existing_demo
          return "mix metrics: no demo.wav found (render with /dilla generate first)" unless path

          Master::Voice::MixMetrics.brief(path)
        rescue StandardError => e
          "mix metrics unavailable: #{e.message}"
        end

        def read_truncated(rel)
          path = File.join(Master::ROOT, rel)
          return unless File.exist?(path)

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
          return sound_domain_context if @mode[:preset_key] == "sound_critique"
          return dilla_domain_context if @mode[:preset_key] == "dilla_critique"
        end

        def dilla_domain_context
          <<~CTX
          Review the Dilla audio engine (tools/dilla) and any measured mix metrics.
          Goal: best possible pad-forward single-style render.
          Evaluate spectral hierarchy (pad vs sub), HF air, presence, groove density,
          headroom/crest, curated harmony, and platform loudness.
          Process: each persona critiques → multi-solution ideation per issue → cherry-pick best.
          Implementation must stay inside existing engine knobs and MASTER commands — no parallel crit stack.
        CTX
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
          return dilla_brief if %w[sound_critique dilla_critique].include?(@mode[:preset_key])
        end

        def platform_profile_brief
          if defined?(Master::Design::PlatformProfiles)
            [
              Master::Design::PlatformProfiles.brief(:brutal_minimal),
              Master::Design::PlatformProfiles.brief(:medium),
              Master::Design::PlatformProfiles.brief(:new_yorker),
            ].join("\n")
          else
            "Platform design profiles unavailable; default to content-first measurable critique."
          end
        rescue StandardError => e
          "Platform profile policy failed to load: #{e.message}."
        end

        def dilla_brief
          Master::Voice::Dilla.council_brief
        end

        def ideation_value(ir)
          return "" if ir.respond_to?(:err?) && ir.err?

          ir.respond_to?(:value) ? ir.value : ir
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

          (wa & wb).size.to_f / [wa.size, wb.size].max
        end
      end
    end
  end
end
