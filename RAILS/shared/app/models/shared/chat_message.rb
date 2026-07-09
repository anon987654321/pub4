# frozen_string_literal: true

module Shared
  class ChatMessage < ApplicationRecord
    self.table_name = "shared_chat_messages"

    belongs_to :sender, class_name: "User", optional: true
    belongs_to :chatable, polymorphic: true, optional: true

    validates :body, presence: true, length: { maximum: 2_000 }

    scope :recent, -> { order(created_at: :asc) }
    scope :anonymous, -> { where(anonymous: true) }

    after_create_commit { broadcast_append_later_to stream_name }

    def display_name
      return "Anonymous" if anonymous? || sender.blank?

      sender.respond_to?(:display_name) ? sender.display_name : sender.email
    end

    private

    def stream_name
      chatable ? "shared:chat:#{chatable_type}:#{chatable_id}" : "shared:chat:global"
    end
  end
end
