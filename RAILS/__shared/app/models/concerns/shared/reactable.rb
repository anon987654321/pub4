# frozen_string_literal: true

module Shared
  module Reactable
    extend ActiveSupport::Concern

    # Only brgen ships a Reaction model and a reactions table. amber and
    # bsdports gate their social stack behind *_SOCIAL until the migrations
    # land (see bsdports/config/routes.rb), so declaring the association there
    # made `dependent: :destroy` raise "no such table: reactions" on every
    # destroy — deleting a bsdports comment 500'd. Degrade instead, the way
    # Shared::ActivityTrackable already does for its own missing backing table.
    #
    # const_defined? reads Zeitwerk's autoload entry, so this needs no database
    # connection at class-definition time.
    def self.backed?
      Object.const_defined?(:Reaction)
    end

    # strict_loading: false, here and on every other `dependent: :destroy` in
    # these concerns. ApplicationRecord sets strict_loading_by_default, and a
    # destroy cascade *must* load its dependents to delete them — there is no
    # preload that avoids it, so strict loading on such an association can only
    # ever produce a crash, never catch an N+1 worth catching. Before this,
    # destroying any reactable/votable/commentable record that had been found by
    # id (which is every controller `destroy` action) raised
    # StrictLoadingViolationError.
    included do
      if Shared::Reactable.backed?
        has_many :reactions, as: :reactable, dependent: :destroy, strict_loading: false, inverse_of: :reactable
      end
    end

    def reacted_by?(user, kind: "like")
      return false unless user && reactions_available?

      reactions.exists?(user:, kind:)
    end

    def reaction_count(kind = nil)
      return 0 unless reactions_available?

      scope = reactions
      scope = scope.where(kind:) if kind.present?
      scope.count
    end

    private

    def reactions_available?
      self.class.reflect_on_association(:reactions).present?
    end
  end
end
