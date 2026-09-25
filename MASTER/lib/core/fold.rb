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
        effect = @model.propose(@memory.context, verbs: @world.verbs, scope: @memory.proof.scope)

        case @law.admit(effect, @memory)
        in Verdict::Block(reason:, by:)
          observation = Observation.no("refused by #{by}: #{reason}")
          @memory.record(effect, observation)
          emit(turn, effect, observation)
        in Verdict::Request(effect: asked, prompt:, reason:, by:)
          done = approve(turn, asked, prompt:, reason:, by:)
          return done if done
        in Verdict::Allow(effect: admitted)
          done = apply(turn, admitted)
          return done if done
        end
      end

      Done.new(reason: :max_turns, turns: @max_turns, summary: nil)
    end

private

    # A rule wants a person to decide. The question goes through the World like
    # any other effect, so a surface that cannot ask -- a daemon, a test --
    # answers no by saying it has no surface, and the effect does not happen.
    # Refusing on no answer rather than proceeding is the only safe default:
    # the rule already judged this dangerous enough to interrupt for.
    #
    # The refusal is recorded as an observation, so the agent sees why it was
    # stopped and can choose another route, exactly as it does for a Block.
    def approve(turn, effect, prompt:, reason:, by:)
      answer = @world.perform(Effect.ask(prompt))
      return apply(turn, effect) if answer.ok? && affirmative?(answer.detail)

      detail = ["#{by} needs approval", reason, answer.ok? ? nil : answer.detail].compact.join(": ")
      observation = Observation.no(detail)
      @memory.record(effect, observation)
      emit(turn, effect, observation)
      nil
    end

    # Anything that is not a clear yes is a no.
    def affirmative?(answer)
      %w[y yes ja ok approve allow].include?(answer.to_s.strip.downcase)
    end

    # The admitted half of the loop. Returns Done when the effect ends the fold
    # and nil to take another turn — extracted from `run` so that method stays
    # under DENSITY's 20 code lines without the fold gaining a new direct file.
    # The direct seven-file invariant and recursive core ratchet are enforced in
    # data/spine.yml. See TODO.md, "The fold spine
    # had never been scanned".
    def apply(turn, admitted)
      if admitted.done?
        observation = Observation.ok("done")
        @memory.record(admitted, observation)
        emit(turn, admitted, observation)
        return Done.new(reason: :complete, turns: turn, summary: admitted.args[:summary])
      end

      # Only an effect that can change the tree has anything to roll back. A
      # checkpoint is a `git diff` per turn, and a failed read or ask came back
      # carrying "rollback skipped" about a tree it never touched.
      mutating = %i[write exec git].include?(admitted.verb)
      checkpoint = @world.checkpoint if mutating
      observation = @world.perform(admitted)
      observation = undo(checkpoint, admitted, observation) if mutating && observation.err?
      @memory.record(admitted, observation)
      emit(turn, admitted, observation)
      nil
    end

    # The effect goes with the checkpoint: rollback undoes what THIS effect
    # touched, and without knowing which effect failed it can only guess at the
    # blast radius — which it used to do with a tree-wide reset.
    #
    # What rollback reports rides on the failure, because the agent's next move
    # depends on it: a write that was undone left the tree as it was, and an
    # effect that could not be undone did not. A clean rollback of anything but
    # a write says nothing the agent needs.
    def undo(checkpoint, effect, observation)
      undone = @world.rollback(checkpoint, effect)
      return observation if undone.ok? && effect.verb != :write

      Observation.no("#{observation.message} [#{undone.message}]")
    end

    def emit(turn, effect, observation)
      @observer&.call(turn:, effect:, observation:)
    end
  end
end
