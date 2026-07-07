# frozen_string_literal: true

module Master::Kernel
  # Kernel — the fold. This is the whole control flow of the agent, and it fits
  # on a screen on purpose. The model proposes an Effect; the Constitution
  # admits or blocks it; the World performs what was admitted; the Memory
  # records the outcome and the loop turns again until the model is done.
  #
  # There is no pipeline of stages, no council subsystem, no scan/fix polling.
  # Capability lives in the World, judgement lives in the Constitution, the
  # Kernel only sequences them. To add an ability, add an Effect handler; to add
  # a constraint, add a rule. The spine never grows.
  class Fold
    Done = Data.define(:reason, :turns, :summary)

    def initialize(model:, constitution:, world:, memory:, max_turns: 40)
      @model = model
      @law = constitution
      @world = world
      @memory = memory
      @max_turns = max_turns
    end

    def run(goal)
      @memory.note(:goal, goal)

      @max_turns.times do |turn|
        effect = @model.propose(@memory.context, verbs: @world.verbs)

        case @law.admit(effect, @memory)
        in Verdict::Block(reason:, by:)
          observation = Observation.no("refused by #{by}: #{reason}")
          @memory.record(effect, observation)
          next
        in Verdict::Allow(effect: admitted)
          if admitted.done?
            @memory.record(admitted, Observation.ok("done"))
            return Done.new(reason: :complete, turns: turn, summary: admitted.args[:summary])
          end

          checkpoint = @world.checkpoint
          observation = @world.perform(admitted)
          @memory.record(admitted, observation)
          @world.rollback(checkpoint) if observation.err?
        end
      end

      Done.new(reason: :max_turns, turns: @max_turns, summary: nil)
    end
  end
end
