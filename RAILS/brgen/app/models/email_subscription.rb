# frozen_string_literal: true

class EmailSubscription < ApplicationRecord
  before_create :generate_token

  # normalizes (not a bare before_validation) so finder args normalize too:
  # "Foo@X.com " and "foo@x.com" resolve to one row instead of inserting a
  # case/whitespace duplicate past the uniqueness check.
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :confirmed, -> { where(confirmed: true) }
  scope :marketing_opted_in, -> { confirmed.where(agreed_to_marketing: true) }

  def confirm!
    update!(confirmed: true, confirmed_at: Time.current)
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
end
