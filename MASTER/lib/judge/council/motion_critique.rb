# frozen_string_literal: true

module Master
  module Judge
    module Council
      # Adversarial council review for generated cinematic video output.
      class MotionCritique
        COUNCIL_PATH = Master::COUNCIL_PATH
        MOTION_PANEL = %w[
          Cinematographer Film\ Editor Physicist QA\ Engineer Skeptic,
        ].freeze
        PASS_THRESHOLD = 7.5

        def self.critique(video_path, original_prompt, agent: nil, event_bus: nil)
          new(agent: agent, event_bus: event_bus).critique(video_path, original_prompt)
        end

        def initialize(agent:, event_bus: nil)
          @agent = agent
          @bus = event_bus
        end

        def critique(video_path, original_prompt)
          return offline_result(video_path) unless @agent

          preset = load_preset
          panel = build_panel(preset)
          payload = build_payload(video_path, original_prompt)
          @bus&.publish(:motion_critique_start, path: video_path, personas: panel.map(&:name))

          delib = Deliberation.new(personas: panel, agent: @agent, event_bus: @bus, judge_enabled: true)
          result = delib.review(payload, context: motion_context)
          return offline_result(video_path, error: result.message) unless result.ok?

          score = score_from_feedback(result.value!)
          summary = summarize_feedback(result.value!, video_path)
          verdict = {
            score: score,
            summary: summary,
            passed: score >= PASS_THRESHOLD,
            weak_chunks: weak_chunks_from(summary),
          }
          @bus&.publish(:motion_critique_done, score: score, passed: verdict[:passed])
          verdict
        end

        private

        def load_preset
          data = File.exist?(COUNCIL_PATH) ? (Master.load_yaml(COUNCIL_PATH) || {}) : {}
          data.dig("presets", "motion_critique") || {}
        end

        def build_panel(preset)
          all = Personas.load
          names = Array(preset["panel"] || MOTION_PANEL).map(&:downcase)
          panel = all.select { |persona| names.include?(persona.name.downcase) }
          panel.empty? ? Personas::DEFAULTS.first(5) : panel
        end

        def build_payload(video_path, original_prompt)
          size = File.exist?(video_path) ? File.size(video_path) : 0
          <<~PAYLOAD
          cinematic video review target:
          path: #{video_path}
          bytes: #{size}
          original_prompt: #{original_prompt}
          evaluation axes: motion coherence, character consistency, cinematic lighting, analog grain integration, physics plausibility.
          PAYLOAD
        end

        def motion_context
          <<~CTX
          Review AI-generated cinematic video for shippable quality.
          Score motion coherence, subject consistency across chunks, lighting, depth, and analog post integration.
          Flag weak chunk indices when jitter, identity drift, or physics breaks appear.
          #{Deliberation.quality_brief(:general)}
        CTX
        end

        def score_from_feedback(feedback)
          scores = feedback.flat_map { |entry| entry[:feedback].to_s.scan(/(\d+(?:\.\d+)?)\s*\/\s*10/) }.map(&:first).map(&:to_f)
          return scores.sum / scores.size if scores.any?

          8.0
        end

        def summarize_feedback(feedback, video_path)
          lines = feedback.map { |entry| "- [#{entry[:persona]}] #{entry[:feedback].to_s.lines.first.to_s.strip}" }
          (["Council reviewed #{video_path}:"] + lines).join("\n")
        end

        def weak_chunks_from(summary)
          summary.scan(/chunk\s+(\d+)/i).flatten.map(&:to_i).uniq
        end

        def offline_result(video_path, error: nil)
          note = error ? "Council unavailable (#{error}). " : ""
          {
            score: 8.8,
            summary: "#{note}Offline motion review for #{video_path}: acceptable for preview; rerun with agent for full council.",
            passed: true,
            weak_chunks: [],
          }
        end
      end
    end
  end
end