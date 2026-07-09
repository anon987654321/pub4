# frozen_string_literal: true

class Volunteer < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  include Shared::GeoLocatable
  belongs_to :user, optional: true
  has_many :shifts, dependent: :destroy

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :available, -> { where(active: true) }

  after_create_commit { broadcast_append_later_to "hjerterom:volunteers" }
end
