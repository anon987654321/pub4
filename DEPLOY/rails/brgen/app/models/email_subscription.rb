class EmailSubscription < ApplicationRecord
  before_create :generate_token

  validates :email, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :confirmed, -> { where(confirmed: true) }

  def confirm!
    update!(confirmed: true, confirmed_at: Time.current)
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end
end
