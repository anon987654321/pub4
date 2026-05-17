class User < ApplicationRecord
  has_secure_password

  has_one :profile, dependent: :destroy
  has_one :creator_profile, dependent: :destroy
  has_one :privacy_setting, dependent: :destroy

  has_many :posts,           dependent: :destroy
  has_many :items,           dependent: :destroy
  has_many :outfits,         dependent: :destroy
  has_many :planned_outfits, dependent: :destroy
  has_many :style_preferences, dependent: :destroy
  has_many :packing_lists, dependent: :destroy
  has_many :recommendations, dependent: :destroy
  has_many :identity_verifications, dependent: :destroy
  has_many :consent_events, dependent: :destroy
  has_many :declutter_reviews, dependent: :destroy
  has_many :declutter_challenges, dependent: :destroy
  has_many :declutter_outcomes, dependent: :destroy

  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :follows_as_followee, class_name: "Follow", foreign_key: :followee_id, dependent: :destroy
  has_many :following,       through: :follows_as_follower, source: :followee
  has_many :followers,       through: :follows_as_followee, source: :follower
  has_many :sessions,        dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  after_create :ensure_identity_records

  broadcasts_refreshes

  def following?(other) = follows_as_follower.exists?(followee: other)
  def feed_posts        = Post.where(user: [self] + following.to_a).recent

  def public_creator? = creator_profile&.public? || false
  def wardrobe_public? = privacy_setting&.public_wardrobe? || false
  def declutter_summary = DeclutterDashboardService.new(self).summary

  private

  def ensure_identity_records
    create_profile! unless profile
    create_privacy_setting! unless privacy_setting
  end
end
