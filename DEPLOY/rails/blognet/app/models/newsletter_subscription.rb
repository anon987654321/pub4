# frozen_string_literal: true

class NewsletterSubscription < ApplicationRecord
  belongs_to :blog

  before_validation :ensure_token, on: :create

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :email, uniqueness: { scope: :blog_id }

  scope :active, -> { where(active: true) }

  def confirm!
    update!(confirmed_at: Time.current, active: true)
  end

  private

  def ensure_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end
end