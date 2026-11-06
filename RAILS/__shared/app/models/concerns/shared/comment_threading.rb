# frozen_string_literal: true

# The self-referential parent/reply/roots shape was hand-duplicated
# identically across amber, brgen, and bsdports' Comment models. Their
# commentable association (polymorphic vs. a fixed belongs_to :port) and
# content length limits differ deliberately and stay per-app — only the
# threading structure that was byte-for-byte identical moves here.
module Shared
  module CommentThreading
    extend ActiveSupport::Concern

    included do
      belongs_to :parent, class_name: "Comment", optional: true
      has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy, strict_loading: false,
               inverse_of: :parent

      scope :roots, -> { where(parent_id: nil).order(created_at: :asc) }
    end

    def root? = parent_id.nil?

    # A comment others have answered leaves a tombstone when its author deletes
    # it: the words and the author go, the row stays, and the replies keep their
    # place in the thread. dependent: :destroy took the whole subtree with it.
    # Only where the table has deleted_at (brgen); elsewhere a delete is a delete.
    def tombstoned? = has_attribute?(:deleted_at) && deleted_at.present?

    def discard!
      return destroy_and_sweep! unless has_attribute?(:deleted_at) && replies.exists?

      update_columns(deleted_at: Time.current, content: "", updated_at: Time.current)
      try(:broadcast_tombstone)
      self
    end

    private

    # A tombstone whose last reply goes has nothing left to hold in place.
    def destroy_and_sweep!
      destroy!
      return self unless parent_id && has_attribute?(:deleted_at)

      parent = self.class.find_by(id: parent_id)
      parent.discard! if parent&.tombstoned? && parent.replies.none?
      self
    end
  end
end
