# frozen_string_literal: true

class ReactionToggle
  def self.call(user:, reactable:, kind: "like")
    new(user:, reactable:, kind:).call
  end

  def initialize(user:, reactable:, kind:)
    @user = user
    @reactable = reactable
    @kind = kind.to_s.presence || "like"
  end

  def call
    reaction = Reaction.find_by(user:, reactable:, kind:)
    if reaction
      reaction.destroy!
      changed = false
    else
      reaction = Reaction.create!(user:, reactable:, kind:)
      changed = true
    end

    Shared::EventEmitter.call("brgen.reaction.toggled", user_id: user.id, target: reactable_gid, kind:, active: changed) if defined?(Shared::EventEmitter)
    changed
  end

  private

  attr_reader :user, :reactable, :kind

  def reactable_gid
    reactable.respond_to?(:to_global_id) ? reactable.to_global_id.to_s : "#{reactable.class.name}:#{reactable.id}"
  end
end
