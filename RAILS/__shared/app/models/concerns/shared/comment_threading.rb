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
  end
end
