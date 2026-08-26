# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password

  has_one :profile, dependent: :destroy
  has_one :creator_profile, dependent: :destroy
  has_one :privacy_setting, dependent: :destroy

  has_many :posts,           dependent: :destroy
  has_many :comments,        dependent: :destroy
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
  has_many :connections_requested, class_name: "Connection", foreign_key: :requester_id, dependent: :destroy
  has_many :connections_received, class_name: "Connection", foreign_key: :addressee_id, dependent: :destroy
  has_many :live_streams, dependent: :destroy
  has_many :sent_messages, class_name: "Message", foreign_key: :sender_id, dependent: :destroy
  has_many :received_messages, class_name: "Message", foreign_key: :recipient_id, dependent: :destroy

  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :follows_as_followee, class_name: "Follow", foreign_key: :followee_id, dependent: :destroy
  has_many :following,       through: :follows_as_follower, source: :followee
  has_many :followers,       through: :follows_as_followee, source: :follower
  has_many :sessions,        dependent: :destroy, inverse_of: :user

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true

  after_create :ensure_identity_records, unless: :guest?

  def guest? = has_attribute?(:guest) && self[:guest]

  def display_name
    return "anon" if guest?

    profile&.display_name.presence || email_address.to_s.split("@").first
  end

  after_commit :broadcast_live_refresh

  def broadcast_live_refresh
    broadcast_refresh_to self
  end

  def following?(other) = follows_as_follower.exists?(followee: other)

  def connected_with?(other)
    return false if other.blank? || other.id == id

    Connection.accepted.where(requester_id: id, addressee_id: other.id)
              .or(Connection.accepted.where(requester_id: other.id, addressee_id: id))
              .exists?
  end

  def messageable_users
    requested = Connection.accepted.where(requester_id: id).select(:addressee_id)
    received = Connection.accepted.where(addressee_id: id).select(:requester_id)
    User.where(id: requested).or(User.where(id: received)).includes(:profile).order(:email_address)
  end
  # A subquery over the join table, not `following.to_a`.
  #
  # User is strict_loading, so materialising the association raised
  # StrictLoadingViolationError for every signed-in visitor and PostsController#feed
  # was a 500 nobody had seen — the surface had no test until the shared affiliate
  # band was placed on it. `following?` and `messageable_users` above already query
  # their join tables directly for the same reason; this is the one that did not.
  #
  # It also stops loading every followed user into memory to throw them away: the
  # ids are all the WHERE needs.
  def feed_posts
    followee_ids = Follow.where(follower_id: id).select(:followee_id)
    Post.where(user_id: followee_ids).or(Post.where(user_id: id)).recent
  end

  def public_creator? = creator_profile&.public? || false
  def wardrobe_public? = privacy_setting&.public_wardrobe? || false
  def declutter_summary = DeclutterDashboard.new(self).summary

  private

  def ensure_identity_records
    strict_loading!(false) do
      create_profile!
      create_privacy_setting!
    end
  end
end
