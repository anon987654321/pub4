# frozen_string_literal: true

module Master::Core
  # Core — the fold. This is the whole control flow of the agent, and it fits
  # on a screen on purpose. The model proposes an Effect; the Constitution
  # admits or blocks it; the World performs what was admitted; the Memory
  # records the outcome and the loop turns again until the model is done.
  #
  # There is no pipeline of stages, no council subsystem, no scan/fix polling.
  # Capability lives in the World, judgement lives in the Constitution, the
  # Core only sequences them. To add an ability, add an Effect handler; to add
  # a constraint, add a rule. The spine never grows.
  class Fold
    Done = Data.define(:reason, :turns, :summary)

    # observer, if given, is called once per turn with (turn:, effect:, observation:)
    # after the outcome is recorded. It only watches — it cannot change the fold —
    # so a host (a CLI, a dashboard) can stream turns without the spine growing.
    def initialize(model:, constitution:, world:, memory:, max_turns: 40, observer: nil)
      @model = model
      @law = constitution
      @world = world
      @memory = memory
      @max_turns = max_turns
      @observer = observer
    end

    def run(goal)
      @memory.note(:goal, goal)

      @max_turns.times do |turn|
        effect = @model.propose(@memory.context, verbs: @world.verbs)

        case @law.admit(effect, @memory)
        in Verdict::Block(reason:, by:)
          observation = Observation.no("refused by #{by}: #{reason}")
          @memory.record(effect, observation)
          emit(turn, effect, observation)
          next
        in Verdict::Allow(effect: admitted)
          if admitted.done?
            observation = Observation.ok("done")
            @memory.record(admitted, observation)
            emit(turn, admitted, observation)
            return Done.new(reason: :complete, turns: turn, summary: admitted.args[:summary])
          end

          checkpoint = @world.checkpoint
          observation = @world.perform(admitted)
          @memory.record(admitted, observation)
          @world.rollback(checkpoint) if observation.err?
          emit(turn, admitted, observation)
        end
      end

      Done.new(reason: :max_turns, turns: @max_turns, summary: nil)
    end

    private

    def emit(turn, effect, observation)
      @observer&.call(turn:, effect:, observation:)
    end
  end
end
