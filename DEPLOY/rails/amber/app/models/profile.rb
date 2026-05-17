class Profile < ApplicationRecord
  belongs_to :user
  has_one_attached :avatar

  validates :display_name, length: { maximum: 80 }
  validates :bio, length: { maximum: 500 }

  enum :visibility, { private_profile: "private", followers_only: "followers", public_profile: "public" }, default: :private_profile

  def name
    display_name.presence || user.email_address.to_s.split("@").first
  end
end
