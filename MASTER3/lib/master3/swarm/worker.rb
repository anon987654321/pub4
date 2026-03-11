# frozen_string_literal: true

module Master3
  module Swarm
    # Base worker — receives only the context slice it needs (need-to-know)
    class Worker
      attr_reader :role, :result

      def initialize(agent:, event_bus: nil)
        @agent    = agent
        @bus      = event_bus
        @role     = self.class.name.split("::").last.downcase
        @result   = nil
      end

      # Execute a task with a minimal context slice
      # context_slice: only what this worker needs — not the full session
      def call(task:, context_slice: {})
        prompt = build_prompt(task, context_slice)
        @bus&.publish(:swarm_worker_start, role: @role, task: task[0..60])

        raw = @agent.chat_raw(prompt, system: worker_system_prompt)
        @result = parse_result(raw)

        @bus&.publish(:swarm_worker_done, role: @role, ok: @result.ok?)
        @result
      rescue => e
        Result.err("worker #{@role}: #{e.message}", category: :unknown)
      end

      private

      def worker_system_prompt
        "You are a specialized #{@role} agent. #{role_description}\n" \
          "Respond only with what is asked. No preamble. No meta-commentary."
      end

      # Subclasses override
      def role_description = "General-purpose assistant."
      def build_prompt(task, ctx) = "#{ctx_summary(ctx)}\n\nTask: #{task}"
      def parse_result(raw)       = Result.ok(raw.to_s.strip)

      def ctx_summary(ctx)
        return "" if ctx.empty?
        ctx.map { |k, v| "#{k.to_s}: #{v.to_s}" }.join("\n")
      end
    end
  end
end
