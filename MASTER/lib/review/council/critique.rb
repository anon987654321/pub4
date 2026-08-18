# frozen_string_literal: true

module Master
  module Review
    module Council
      # Mode-dispatched council critique. Replaces UiCritique + SoundCritique.
      #
      # Orchestration only: pick the panel, assemble the payload, deliberate,
      # ideate, cherry-pick. The mode table lives in Critique::Modes, the panel's
      # briefing in Critique::Context, and the ranking in Critique::CherryPick.
      class Critique
        MODES = Modes::TABLE

        def initialize(mode:, agent:, event_bus: nil, audio_path: nil, files: nil)
          @mode = MODES.fetch(mode) { raise ArgumentError, "unknown critique mode: #{mode}" }
          @agent = agent
          @bus = event_bus
          @audio_path = audio_path
          @files_override = files
        end

        def run
          preset = load_preset
          panel = build_panel(preset)
          payload = build_payload(preset)
          @bus&.publish(@mode[:start_event], files: payload[:files], personas: panel.map(&:name))

          result = deliberate(panel, payload)
          return result unless result.ok?

          feedback = result.value!
          ideation_result = ideate(preset, feedback:)
          cherry = CherryPick.call(feedback, ideation_result)
          @bus&.publish(@mode[:done_event], cherry_picks: cherry.size)
          harvest = harvest_path(payload:, feedback:, ideation_result:, cherry:)
          Master::Result.ok({
            feedback:,
            ideas: CherryPick.ideation_value(ideation_result),
            cherry_picks: cherry,
            metrics: payload[:metrics],
            mode: @mode[:preset_key],
            harvest:,
          })
        end

        private

        def deliberate(panel, payload)
          delib = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
          delib.review(payload[:combined], context: build_context)
        end

        def ideate(preset, feedback: nil)
          Ideation.new(agent: @agent, event_bus: @bus).ideate(
            ideation_prompt(feedback),
            constraints: @mode[:constraints],
            cycles: (preset["cycles"] || @mode[:cycles_default]).to_i,
          )
        end

        # Ideation used to run on the mode's canned prompt alone, blind to what
        # the panel just found — proposals for nothing in particular, ranked
        # against complaints they never addressed. The panel's issues ARE the
        # prompt: several proposals per issue, so the challenge round has
        # something to eliminate.
        def ideation_prompt(feedback)
          issues = Array(feedback).filter_map { |entry| entry[:feedback].to_s.lines.first&.strip }
                                  .reject(&:empty?).uniq.first(12)
          return @mode[:ideation_prompt] if issues.empty?

          <<~PROMPT
            #{@mode[:ideation_prompt]}

            The council raised these issues. Propose at least two distinct
            fixes for each, so the weaker can be discarded:
            #{issues.map { |issue| "- #{issue}" }.join("\n")}
          PROMPT
        end

        def harvest_path(payload:, feedback:, ideation_result:, cherry:)
          Harvest.write(
            mode: @mode[:preset_key],
            files: payload[:files],
            feedback:,
            ideas: CherryPick.ideation_value(ideation_result),
            cherry:,
          )
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "Critique.harvest", severity: :load_bearing)
          nil
        end

        def build_context
          Context.new(preset_key: @mode[:preset_key], quality_kind: @mode[:quality_kind]).to_s
        end

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
          files = if Array(@files_override).any?
                    @files_override
                  else
                    Array(preset["files"]).any? ? preset["files"] : @mode[:files]
                  end
          combined = files.filter_map { |rel| read_truncated(rel) }.join("\n\n")
          metrics = mix_metrics_block if @mode[:include_mix_metrics]
          combined = [metrics, combined].compact.join("\n\n") if metrics
          { combined:, files:, metrics: }
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
          # @files_override entries (whatever /scan or /fix just processed)
          # come in as absolute paths already; preset/mode file lists are
          # MASTER-root-relative.
          path = rel.to_s.start_with?("/") ? rel.to_s : File.join(Master::ROOT, rel)
          return unless File.file?(path)

          raw = File.read(path, encoding: "UTF-8")
          raw = raw.byteslice(0, @mode[:max_bytes]) + "\n... [truncated]" if raw.bytesize > @mode[:max_bytes]
          "file: #{rel}\n#{raw}"
        end
      end
    end
  end
end
