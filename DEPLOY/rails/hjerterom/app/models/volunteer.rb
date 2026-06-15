# frozen_string_literal: true

class Volunteer < ApplicationRecord
  # Engine-ize Shared
  include Shared.concern(:Notifiable) rescue nil
  include Shared.concern(:Reactable) rescue nil
  include Shared.concern(:GeoLocatable) rescue nil
  has_many :shifts, dependent: :destroy

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :available, -> { where(active: true) }

  after_create_commit { broadcast_append_later_to "hjerterom:volunteers" }
end
