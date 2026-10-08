# frozen_string_literal: true

module Shared
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
      klass = defined?(::Reaction) ? ::Reaction : Shared::Reaction
      reaction = klass.find_by(user:, reactable:, kind:)
      active = reaction.nil?
      active ? klass.create!(user:, reactable:, kind:) : reaction.destroy!

      Shared::EventEmitter.call("shared.reaction.toggled", user_id: user.id, target: target_label, kind:,
active:) if defined?(Shared::EventEmitter)
      active
    end

    private

    attr_reader :user, :reactable, :kind

    def target_label
      reactable.respond_to?(:to_global_id) ? reactable.to_global_id.to_s : "#{reactable.class.name}:#{reactable.id}"
    end
  end
end
