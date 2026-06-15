# frozen_string_literal: true

class Dating::EventRsvp < ApplicationRecord
  self.table_name = "dating_event_rsvps"

  belongs_to :dating_event, class_name: "Dating::Event"
  belongs_to :user

  STATUSES = %w[going interested].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :dating_event_id }
end