# frozen_string_literal: true

module Shared
  module Reactable
    extend ActiveSupport::Concern

    included do
      has_many :reactions, as: :reactable, dependent: :destroy
    end

    def reacted_by?(user, kind: "like")
      return false unless user

      reactions.exists?(user:, kind:)
    end

    def reaction_count(kind = nil)
      scope = reactions
      scope = scope.where(kind:) if kind.present?
      scope.count
    end
  end
end
