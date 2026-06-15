# frozen_string_literal: true

module Master
  module Judge
    module Council
      # CV02: parallel specialist agents (style/security/perf/soul).
      class Swarm
        SPECIALISTS = %w[style security perf soul].freeze
        WORKER_TIMEOUT = 120

        def initialize(agent:, event_bus: nil)
          @agent = agent
          @bus = event_bus
        end

        def review(artifact, context:)
          threads = SPECIALISTS.map do |role|
            Thread.new { specialist_review(role, artifact, context) }
          end
          results = threads.map { |t| t.join(WORKER_TIMEOUT); t.value }.compact
          @bus&.publish("council:swarm_complete", specialists: results.size)
          results
        rescue StandardError => e
          @bus&.publish("council:swarm_error", error: e.message)
          []
        end

        private

        def specialist_review(role, artifact, context)
          prompt = "You are the #{role} specialist. Review:\n#{artifact.to_s[0, 8000]}\nContext: #{context}"
          { role:, feedback: @agent.ask(prompt).to_s.strip, confidence: 0.7 }
        rescue StandardError => e
          { role:, feedback: "error: #{e.message}", confidence: 0.0 }
        end
      end
    end
  end
end