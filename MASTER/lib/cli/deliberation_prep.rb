# frozen_string_literal: true

module Master
  module CLI
    # DeliberationPrep — ideation pass before Fold on medium+ risk goals.
    module DeliberationPrep
      module_function

      def prepare!(goal:, container:, risk:)
        return unless FoldRisk.ideation_required?(risk)

        agent = container[:agent]
        bus = container[:bus]
        return unless agent

        run_ideation(goal, agent:, bus:, risk:)
      rescue StandardError => e
        container[:bus]&.publish("ideation:error", message: e.message)
        nil
      end

      def run_ideation(goal, agent:, bus:, risk:)
        cycles = constrained_host? ? 1 : 2
        budget = constrained_host? ? 45 : 120
        ideation = Review::Council::Ideation.new(agent:, event_bus: bus)
        bus&.publish("ideation:start", risk:, cycles:)
        result = ideation.ideate(goal, cycles:, budget_seconds: budget)
        if result.err?
          bus&.publish("ideation:error", message: result.message.to_s[0, 200])
          return
        end

        payload = result.value!
        bus&.publish("ideation:done", ideas: payload[:ideas].size)
        payload
      end

      def seed_memory!(memory, payload)
        return memory unless payload

        memory.note(:risk, memory.proof.risk)
        Array(payload[:ideas]).each_with_index do |idea, index|
          memory.note(:approach, "#{index + 1}. #{idea}")
        end
        memory.note(:chosen, payload[:final].to_s)
        memory.proof.mark_ideation_complete!(approaches: Array(payload[:ideas]).size)
        memory
      end

      def constrained_host?
        mb = Master::Core::Memory.host_memory_mb
        mb && mb <= Master::Core::Memory::CONSTRAINED_MB
      end
    end
  end
end
