# frozen_string_literal: true

require "json"

module Master
  module Judge
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know).
    class Worker
      PREFERRED_MODEL = nil
      FALLBACK_MODEL = nil

      UNCERTAINTY_PHRASES = %w[unclear uncertain not\ sure cannot\ determine
                                i\ don't\ know limited\ information probably].freeze

      attr_reader :role, :result, :confidence

      def initialize(agent:, event_bus: nil)
        @agent = agent
        @bus = event_bus
        class_name = self.class.name
        class_parts = class_name.split("::")
        @role = class_parts.last.downcase
        @result = nil
        @confidence = 1.0
      end

      def call(task:, context_slice: {})
        prompt = build_prompt(task, context_slice)
        @bus&.publish(:swarm_worker_start, role: @role, task: task[0..60])

        raw = ask_with_fallback(prompt)
        @result = parse_result(raw)
        @confidence = @result.ok? && @result.value!.is_a?(Hash) ? (@result.value![:confidence] || 1.0) : 0.0

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

      def ask_with_fallback(prompt)
        preferred = self.class::PREFERRED_MODEL
        fallback = self.class::FALLBACK_MODEL
        @agent.ask_once(prompt, model: preferred, system: worker_system_prompt)
      rescue StandardError => e
        raise unless fallback
        @bus&.publish(:swarm_worker_fallback, role: @role, reason: e.class.name)
        @agent.ask_once(prompt, model: fallback, system: worker_system_prompt)
      end

      def parse_result(raw)
        text = raw.to_s.strip
        Result.ok({ text:, confidence: uncertainty_confidence(text) })
      end

      def uncertainty_confidence(text)
        hits = UNCERTAINTY_PHRASES.count { |p| text.downcase.include?(p) }
        [1.0 - (hits.to_f / [UNCERTAINTY_PHRASES.size, 1].max * 0.5), 0.0].max.round(2)
      end

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k}: #{v}" }.join("\n")
      end
    end
  end
  end
end
