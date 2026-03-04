# frozen_string_literal: true

module Chamber
  class Deliberation
    DEFAULT_LIMIT = 50

    def deliberate(session:, actor:, motion_id:, limit: DEFAULT_LIMIT, now: Time.current)
      motion = load_motion(motion_id)
      guard_actor!(actor, motion)

      build_context(session: session, actor: actor, motion: motion, now: now).then { |ctx|
        validate_context(ctx)
      }.then { |ctx|
        apply_votes(ctx, limit: limit)
      }.then { |ctx|
        finalize(ctx)
      }
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def build_context(session:, actor:, motion:, now:)
      { session: session, actor: actor, motion: motion, now: now, votes: [] }
    end

    def validate_context(ctx)
      motion = ctx.fetch(:motion)
      raise ArgumentError, "motion is not open" unless motion.open?

      ctx
    end

    def apply_votes(ctx, limit:)
      motion = ctx.fetch(:motion)
      votes = motion.votes.order(created_at: :asc).limit(limit).to_a

      ctx.merge(votes: votes)
    end

    def finalize(ctx)
      motion = ctx.fetch(:motion)
      votes = ctx.fetch(:votes)

      result = motion.tally(votes)
      motion.update!(result: result, deliberated_at: ctx.fetch(:now))

      ctx.merge(result: result)
    end

    private

    def load_motion(motion_id)
      Motion.includes(:proposer, :participants, votes: :voter).find(motion_id)
    rescue ActiveRecord::StatementInvalid
      raise ActiveRecord::RecordNotFound
    end

    def guard_actor!(actor, motion)
      raise ArgumentError, "actor required" if actor.nil?
      raise ArgumentError, "not permitted" unless motion.participants.include?(actor)
    end
  end
end