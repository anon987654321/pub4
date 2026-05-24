# frozen_string_literal: true

module Shared
  class Post < ApplicationRecord
    self.table_name = "shared_posts"

    belongs_to :user, optional: true
    belongs_to :postable, polymorphic: true, optional: true

    validates :body, presence: true, length: { maximum: 5_000 }

    scope :frontpage, -> { where(frontpage: true).order(created_at: :desc) }
    scope :recent, -> { order(created_at: :desc) }
    scope :anonymous, -> { where(anonymous: true) }

    after_create_commit { broadcast_prepend_later_to stream_name }
    after_update_commit { broadcast_replace_later_to stream_name }

    def display_name
      return "Anonymous" if anonymous? || user.blank?

      user.respond_to?(:display_name) ? user.display_name : user.email
    end

    private

    def stream_name
      postable ? "shared:posts:#{postable_type}:#{postable_id}" : "shared:posts:frontpage"
    end
  end
end
