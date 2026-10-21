# frozen_string_literal: true

class Comment < ApplicationRecord
  # Engine-ize Shared
  include Shared::Reactable
  include Shared::Notifiable
  include Shared::CommentThreading

  belongs_to :user
  belongs_to :port

  validates :content, presence: true, length: { maximum: 5000 }
  validate { errors.add(:parent_id, "does not match port") if parent && parent.port_id != port_id }

  after_create_commit -> { broadcast_append_to [ port, "comments" ] }
end
