# frozen_string_literal: true

require_relative "../ground/assistant_tasks"
require_relative "../result"

module Master
  module Io
    # Governed adapter around the owner-local durable task ledger.
    class AssistantTasks
      TIER = :guarded
      NAME = "assistant_tasks"
      DESCRIPTION = "Maintain durable personal tasks and step-level evidence without executing actions.".freeze

      def initialize(root: Master::ROOT, governor:, event_bus: nil)
        @root = root
        @governor = governor
        @bus = event_bus
      end

      def call(action:, **args)
        if Fiber[:master_visitor] == true
          return Result.err("assistant_tasks: owner-local only; visitor access is denied", category: :policy)
        end

        verb = action.to_s
        permitted = @governor.permit?(NAME, TIER, verb)
        return permitted if permitted.err?

        result = Ground::AssistantTasks.new(root: @root, bus: @bus).call(action: verb, **args)
        @bus&.publish("tool:after", tool: NAME, action: verb)
        Result.ok(result)
      rescue Ground::AssistantTasks::Error, ArgumentError => e
        Result.err("assistant_tasks: #{e.message}", category: :validation)
      rescue StandardError => e
        Result.err("assistant_tasks: #{e.class}: #{e.message}", category: :infrastructure)
      end
    end
  end
end
