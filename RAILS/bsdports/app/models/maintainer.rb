# frozen_string_literal: true

class Maintainer < ApplicationRecord
  # Engine-ize Shared
  include Shared::Notifiable
  include Shared::Reactable
  has_many :ports, dependent: :nullify

  # The unique index on maintainers.name existed without this, so a duplicate
  # reached the database and came back as ActiveRecord::RecordNotUnique — a 500,
  # not a form error. The importer resolves a maintainer per port from a free-text
  # field in the ports tree, so a repeat is the ordinary case rather than an
  # adversarial one.
  validates :name, presence: true, uniqueness: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :active, -> { where(active: true) }

  def label
    email.present? ? "#{name} <#{email}>" : name
  end
end
