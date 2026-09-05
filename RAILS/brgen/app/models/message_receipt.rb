# frozen_string_literal: true

class MessageReceipt < ApplicationRecord
  belongs_to :message
  belongs_to :user

  # One receipt per reader per message, matching the unique index. The bulk
  # paths use insert_all and skip this; what it guards is Message#mark_as_read!,
  # which builds through find_or_initialize_by and would otherwise raise
  # RecordNotUnique when two devices open a thread at once.
  validates :user_id, uniqueness: { scope: :message_id }

  scope :read, -> { where.not(read_at: nil) }

  def read? = read_at.present?
  def delivered? = delivered_at.present?
end
