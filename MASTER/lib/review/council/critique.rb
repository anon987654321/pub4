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

        def initialize(mode:, agent:, event_bus: nil, audio_path: nil, files: nil, visual_image: nil, visual_context: nil)
          @mode = MODES.fetch(mode) { raise ArgumentError, "unknown critique mode: #{mode}" }
          @agent = agent
          @bus = event_bus
          @audio_path = audio_path
          @files_override = files
          @visual_image = visual_image
          @visual_context = visual_context
        end

        def run
          preset = load_preset
          panel = build_panel(preset)
          payload = build_payload(preset)
          @bus&.publish(@mode[:start_event], files: payload[:files], personas: panel.map(&:name))

          result = deliberate(panel, payload)
          return result unless result.ok?

          feedback = result.value!
          issues = panel_issue_entries(feedback)
          visual_clean = @mode[:preset_key] == "ui_critique" && issues.empty?
          ideation_result = if visual_clean
                              Master::Result.ok(ideas: [], critiques: [], final: "VISUAL_CLEAN")
                            else
                              ideate(preset, feedback:)
                            end
          cherry = visual_clean ? [] : CherryPick.call(feedback, ideation_result)
          @bus&.publish(@mode[:done_event], cherry_picks: cherry.size, visual_clean:)
          harvest = harvest_path(payload:, feedback:, ideation_result:, cherry:)
          Master::Result.ok({
            feedback:,
            issues:,
            visual_clean:,
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
          delib.review(payload[:combined], context: build_context, image: payload[:visual_image])
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
        # prompt, and each wants a field to choose from: two proposals give the
        # cherry-pick nothing to reject, and twenty restatements of one idea
        # give it nothing either. Materially different means the repairs differ
        # in what they change, not in how they are worded.
        IDEAS_PER_ISSUE = (5..20).freeze

        def ideation_prompt(feedback)
          issues = panel_issues(feedback)
          if issues.empty?
            return @mode[:ideation_prompt] unless @mode[:preset_key] == "ui_critique"

            return "#{@mode[:ideation_prompt]}\n\nNo actionable visual defect remains: output VISUAL_CLEAN exactly."
          end

          <<~PROMPT
            #{@mode[:ideation_prompt]}

            The council raised the issues below. For each one, propose
            #{IDEAS_PER_ISSUE.first} to #{IDEAS_PER_ISSUE.last} materially different repairs — different in what
            they change, not in how they are phrased. Number each proposal and
            name the issue it repairs. The weakest are discarded, so a field of
            near-identical proposals is a field of one.
            #{issues.each_with_index.map { |issue, index| "#{index + 1}. #{issue}" }.join("\n")}
          PROMPT
        end

        # The first line of each critique: the issue, without the argument for it.
        def panel_issues(feedback)
          panel_issue_entries(feedback).map { |entry| entry[:summary] }
        end

        def panel_issue_entries(feedback)
          seen = {}
          Array(feedback).reject { |entry| entry[:persona].to_s == "Judge" }.filter_map do |entry|
            summary = entry[:feedback].to_s.lines.first&.strip.to_s
            next if summary.empty? || seen.key?(summary)

            seen[summary] = true
            {
              persona: entry[:persona].to_s,
              summary: summary,
              feedback: entry[:feedback].to_s,
            }
          end.first(12)
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
          panel = if names.empty?
                    all
                  else
                    chosen = all.select { |persona| names.include?(persona.name.downcase) }
                    chosen.empty? ? Personas::DEFAULTS : chosen
                  end
          localize_panel(panel)
        end

        # CLI-lane sizing (see Deliberation.local_posture?): a full 26-persona
        # panel cannot be heard inside the budget on the claude CLI, so local
        # runs take council.yml's local_panel, veto roles and the Maintainer
        # surviving the cut first.
        def localize_panel(panel)
          return panel unless Deliberation.local_posture?

          cap = Deliberation.local_panel_size
          return panel if panel.size <= cap

          keep = panel.select { |p| (p.respond_to?(:veto?) && p.veto?) || p.name == "Maintainer" }.first(cap)
          keep + (panel - keep).first([cap - keep.size, 0].max)
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
          combined = [@visual_context, combined].compact.join("\n\n") if @visual_context
          { combined:, files:, metrics:, visual_image: @visual_image }
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
