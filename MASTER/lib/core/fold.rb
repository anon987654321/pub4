# frozen_string_literal: true

require "securerandom"

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
    BLOCK_LIMIT = 3

    # observer, if given, is called once per turn with (turn:, effect:, observation:)
    # after the outcome is recorded. It only watches — it cannot change the fold —
    # so a host (a CLI, a dashboard) can stream turns without the spine growing.
    # effect_observer receives :before and :after around every World effect. Unlike
    # the UI observer, failure to publish a lifecycle event stops the fold safely.
    def initialize(model:, constitution:, world:, memory:, max_turns: 40, observer: nil, effect_observer: nil, cancellation: nil)
      if cancellation && !cancellation.respond_to?(:cancelled?)
        raise ArgumentError, "cancellation must respond to cancelled?"
      end

      @model = model
      @cancellation = cancellation
      @law = constitution
      @world = world
      @memory = memory
      @max_turns = max_turns
      @observer = observer
      @effect_observer = effect_observer
      @lifecycle_failure = nil
      @lifecycle_failure_before = false
    end

    def run(goal)
      return cancellation_done(0) if cancellation_requested?

      @memory.note(:goal, goal)
      blocked_effects = Hash.new(0)
      blocked_by = Hash.new(0)

      @max_turns.times do |turn|
        return cancellation_done(turn) if cancellation_requested?

        effect = @model.propose(@memory.context, verbs: @world.verbs, scope: @memory.proof.scope)
        return cancellation_done(turn + 1) if cancellation_requested?

        verdict = @law.admit(effect, @memory)
        return cancellation_done(turn + 1) if cancellation_requested?

        case verdict
        in Verdict::Block(reason:, by:)
          observation = Observation.no("refused by #{by}: #{reason}")
          @memory.record(effect, observation)
          emit(turn, effect, observation)
          blocked_by[by.to_s] += 1
          signature = [effect.verb, by.to_s, reason.to_s]
          blocked_effects[signature] += 1
          if blocked_by[by.to_s] >= BLOCK_LIMIT
            summary = "stopped after #{BLOCK_LIMIT} constitutional blocks by #{by}: #{reason}"
            return Done.new(reason: :blocked, turns: turn + 1, summary:)
          end
          if blocked_effects[signature] >= 2
            summary = "stopped after repeated #{effect.verb} refusal by #{by}: #{reason}"
            return Done.new(reason: :blocked, turns: turn + 1, summary:)
          end
        in Verdict::Request(effect: asked, prompt:, reason:, by:)
          done = approve(turn, asked, prompt:, reason:, by:)
          return done if done
        in Verdict::Allow(effect: admitted)
          done = apply(turn, admitted)
          return done if done
        end
      end

      return cancellation_done(@max_turns) if cancellation_requested?

      Done.new(reason: :max_turns, turns: @max_turns, summary: nil)
    end

private

    def cancellation_requested? = @cancellation&.cancelled? == true

    def cancellation_done(turns)
      reason = @cancellation.respond_to?(:reason) ? @cancellation.reason.to_s.strip : ""
      summary = reason.empty? ? "cancelled" : "cancelled: #{reason}"
      Done.new(reason: :cancelled, turns:, summary:)
    end

    # A rule wants a person to decide. The question goes through the World like
    # any other effect, so a surface that cannot ask -- a daemon, a test --
    # answers no by saying it has no surface, and the effect does not happen.
    # Refusing on no answer rather than proceeding is the only safe default:
    # the rule already judged this dangerous enough to interrupt for.
    #
    # The refusal is recorded as an observation, so the agent sees why it was
    # stopped and can choose another route, exactly as it does for a Block.
    def approve(turn, effect, prompt:, reason:, by:)
      answer = perform_effect(turn, Effect.ask(prompt))
      return trace_failed_done(turn) if @lifecycle_failure
      return apply(turn, effect) if answer.ok? && affirmative?(answer.detail)

      detail = ["#{by} needs approval", reason, answer.ok? ? nil : answer.detail].compact.join(": ")
      observation = Observation.no(detail)
      @memory.record(effect, observation)
      emit(turn, effect, observation)
      return Done.new(reason: :needs_user, turns: turn, summary: detail) if answer.err? && answer.detail.to_s == "no surface to ask"

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
    # data/spine.yml. See the old backlog, "The fold spine
    # had never been scanned".
    def apply(turn, admitted)
      return cancellation_done(turn + 1) if cancellation_requested?

      if admitted.done?
        observation = Observation.ok("done")
        @memory.record(admitted, observation)
        emit(turn, admitted, observation)
        return Done.new(reason: :complete, turns: turn, summary: admitted.args[:summary])
      end

      contract = admitted.reversibility
      rollbackable = contract.restorable?
      checkpoint = @world.checkpoint if rollbackable
      checkpoint_id = checkpoint[:id] if checkpoint
      effect_id = SecureRandom.uuid
      observation = perform_effect(turn, admitted, effect_id:, checkpoint_id:)
      if observation.err?
        observation = undo(checkpoint, admitted, observation, turn:, parent_effect_id: effect_id) if rollbackable && !@lifecycle_failure
        observation = compensate(observation, contract, turn:, parent_effect_id: effect_id,
                                 checkpoint_id:) if contract.compensatable? && !@lifecycle_failure
      end
      @memory.record(admitted, observation)
      emit(turn, admitted, observation)
      return trace_failed_done(turn) if @lifecycle_failure

      nil
    end

    # The effect goes with the checkpoint: rollback undoes what THIS effect
    # touched, and without knowing which effect failed it can only guess at the
    # blast radius — which it used to do with a tree-wide reset.
    #
    # What rollback reports rides on the failure, because the agent's next move
    # depends on it: a write that was undone left the tree as it was, and a
    # write that could not be undone did not.
    def undo(checkpoint, effect, observation, turn:, parent_effect_id:)
      undone = perform_rollback(turn, checkpoint, effect, parent_effect_id:)
      Observation.no("#{observation.message} [#{undone.message}]")
    end

    # Rollback changes repository state, so it has its own required lifecycle
    # pair rather than disappearing behind the failed write's after-event.
    def perform_rollback(turn, checkpoint, effect, parent_effect_id:)
      effect_id = SecureRandom.uuid
      notify_effect(stage: :before, turn:, effect:, effect_id:, operation: :rollback,
                    parent_effect_id:, checkpoint_id: checkpoint[:id])
      return Observation.no("rollback not executed: lifecycle before-event publication failed") if @lifecycle_failure

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      observation = world_rollback(checkpoint, effect)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      notify_effect(stage: :after, turn:, effect:, effect_id:, operation: :rollback,
                    parent_effect_id:, checkpoint_id: checkpoint[:id], observation:, elapsed_ms:)
      observation
    end

    def world_rollback(checkpoint, effect)
      @world.rollback(checkpoint, effect)
    rescue StandardError, SecurityError => e
      Observation.no("#{e.class}: #{e.message}")
    end

    # Run only a declared compensation, only after the original command failed,
    # and only after the same Constitution has admitted it and the operator says
    # yes. The compensation is a new exec effect; no inverse bypasses the check.
    def compensate(failure, contract, turn:, parent_effect_id:, checkpoint_id: nil)
      action = contract.compensation
      inverse = Effect.exec(action.argv)
      case @law.admit(inverse, @memory)
      in Verdict::Block(reason:, by:)
        return Observation.no("#{failure.message} [compensation blocked by #{by}: #{reason}]")
      in Verdict::Request(prompt:, reason:, by:)
        approval_context = "#{by} requested approval: #{reason}. "
        check_prompt = prompt
      in Verdict::Allow
        approval_context = ""
        check_prompt = "The original command failed. Approve compensation #{action.argv.inspect}? #{action.reason}"
      end

      prompt = "#{approval_context}#{check_prompt} Compensation: #{action.argv.inspect}. Reason: #{action.reason}"
      answer = perform_effect(turn, Effect.ask(prompt), operation: :compensation_approval, parent_effect_id:, checkpoint_id:)
      return Observation.no("compensation stopped because lifecycle event publication failed") if @lifecycle_failure

      unless answer.ok? && affirmative?(answer.detail)
        detail = answer.ok? ? "operator declined" : answer.message
        return Observation.no("#{failure.message} [compensation not run: #{detail}]")
      end

      result = perform_effect(turn, inverse, operation: :compensation, parent_effect_id:, checkpoint_id:)
      @memory.record(inverse, result)
      if result.ok?
        Observation.no("#{failure.message} [compensation completed: #{action.argv.join(" ")} — #{result.message}]")
      else
        Observation.no("#{failure.message} [compensation failed: #{action.argv.join(" ")} — #{result.message}]")
      end
    rescue StandardError => e
      Observation.no("#{failure.message} [compensation failed: #{e.class}: #{e.message}]")
    end

    def perform_effect(turn, effect, effect_id: SecureRandom.uuid, operation: :perform, parent_effect_id: nil,
                       checkpoint_id: nil, idempotency_key: nil, deadline_at: nil)
      notify_effect(stage: :before, turn:, effect:, effect_id:, operation:, parent_effect_id:,
                    checkpoint_id:, idempotency_key:, deadline_at:)
      return Observation.no("effect not executed: lifecycle before-event publication failed") if @lifecycle_failure

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      observation = world_observation(effect)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      notify_effect(stage: :after, turn:, effect:, effect_id:, operation:, parent_effect_id:,
                    checkpoint_id:, idempotency_key:, deadline_at:, observation:, elapsed_ms:)
      observation
    end

    def world_observation(effect)
      @world.perform(effect)
    rescue StandardError, SecurityError => e
      Observation.no("#{e.class}: #{e.message}")
    end

    def notify_effect(**event)
      event[:scope] = effect_scope(event[:effect]) unless event.key?(:scope)
      event[:reversibility] ||= event[:effect].reversibility.contract_kind if event[:effect].respond_to?(:reversibility)
      @effect_observer&.call(**event)
    rescue StandardError => e
      @lifecycle_failure_before = true if event[:stage] == :before
      @lifecycle_failure ||= "#{event[:stage]} event publication failed (#{e.class})"
    end

    def trace_failed_done(turn)
      Done.new(reason: :trace_failed, turns: turn + 1,
               summary: "stopped without claiming completion: #{@lifecycle_failure}")
    end

    # The observer hashes this local scope before persistence. Never send the
    # source path, URL, command arguments, note text, or prompt to the event log.
    def effect_scope(effect)
      args = effect.args
      case effect.verb
      when :read, :write
        args[:path] || args["path"]
      when :http
        args[:url] || args["url"]
      when :exec
        Array(args[:argv] || args["argv"]).map(&:to_s).join("\0")
      when :git
        [args[:operation] || args["operation"], *Array(args[:paths] || args["paths"])].join("\0")
      when :note, :ask, :critique
        effect.verb.to_s
      else
        nil
      end
    end

    def emit(turn, effect, observation)
      @observer&.call(turn:, effect:, observation:)
    end
  end
end
