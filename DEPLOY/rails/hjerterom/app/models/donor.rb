# frozen_string_literal: true

class Donor < ApplicationRecord
  has_many :donations, dependent: :nullify

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :active, -> { where(active: true) }

  def contact_label
    [ name, email.presence, phone.presence ].compact.join(" · ")
  end
end
