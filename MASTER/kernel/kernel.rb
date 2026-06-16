# frozen_string_literal: true

module Master
  # Kernel — the fold. This is the whole control flow of the agent, and it fits
  # on a screen on purpose. The model proposes an Effect; the Constitution
  # admits or blocks it; the World performs what was admitted; the Memory
  # records the outcome and the loop turns again until the model is done.
  #
  # There is no pipeline of stages, no council subsystem, no scan/fix polling.
  # Capability lives in the World, judgement lives in the Constitution, the
  # Kernel only sequences them. To add an ability, add an Effect handler; to add
  # a constraint, add a rule. The spine never grows.
  class Kernel
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
        return Done.new(reason: :complete, turns: turn, summary: effect.args[:summary]) if effect.done?

        observation =
          case @law.admit(effect, @memory)
          in Verdict::Allow(effect: admitted) then @world.perform(admitted)
          in Verdict::Block(reason:, by:) then Observation.no("refused by #{by}: #{reason}")
          end

        @memory.record(effect, observation)
        @world.commit(effect.to_s) if observation.ok
      end

      Done.new(reason: :max_turns, turns: @max_turns, summary: nil)
    end
  end
end
