# frozen_string_literal: true

module Master
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know).
    class Worker
      PREFERRED_MODEL = nil

      UNCERTAINTY_PHRASES = %w[unclear uncertain not\ sure cannot\ determine
                                i\ don't\ know limited\ information probably].freeze

      attr_reader :role, :result, :confidence

      def initialize(agent:, event_bus: nil)
        @agent      = agent
        @bus        = event_bus
        @role       = self.class.name.split("::").last.downcase
        @result     = nil
        @confidence = 1.0
      end

      def call(task:, context_slice: {})
        prompt = build_prompt(task, context_slice)
        @bus&.publish(:swarm_worker_start, role: @role, task: task[0..60])

        preferred = self.class::PREFERRED_MODEL
        raw = @agent.ask_once(prompt, model: preferred, system: worker_system_prompt)
        @result, @confidence = parse_result(raw)

        @bus&.publish(:swarm_worker_done, role: @role, ok: @result.ok?)
        @result
      rescue StandardError => e
        Result.err("worker #{@role}: #{e.message}", category: :unknown)
      end

      private

      def worker_system_prompt
        "You are a specialized #{@role} agent. #{role_description}\n" \
          "Respond only with what is asked. No preamble. No meta-commentary."
      end

      def role_description = "General-purpose assistant."
      def build_prompt(task, ctx) = "#{ctx_summary(ctx)}\n\nTask: #{task}"

      def parse_result(raw)
        text = raw.to_s.strip
        hits = UNCERTAINTY_PHRASES.count { |p| text.downcase.include?(p) }
        conf = [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
        [Result.ok({ text: text, confidence: conf }), conf]
      end

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
end
