# frozen_string_literal: true

class Maintainer < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  has_many :ports, dependent: :nullify

  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :active, -> { where(active: true) }

  def label
    email.present? ? "#{name} <#{email}>" : name
  end
end
