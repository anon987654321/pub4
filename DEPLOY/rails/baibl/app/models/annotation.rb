# frozen_string_literal: true

class Annotation < ApplicationRecord
  enum :visibility, { private_note: 0, group_note: 1, public_note: 2 }, default: :private_note

  belongs_to :verse
  belongs_to :user, optional: true

  validates :body, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :publicly_visible, -> { where(visibility: :public_note) }

  after_create_commit { broadcast_prepend_later_to "baibl:annotations" }
  after_update_commit { broadcast_replace_later_to "baibl:annotations" }
end
