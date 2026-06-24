# frozen_string_literal: true

class User < ApplicationRecord
  acts_as_tenant :city, optional: true  # Automatic city scoping based on request TLD/domain

  has_secure_password

  belongs_to :city, optional: true

  has_many :account_merges, dependent: :destroy
  has_many :activity_events, foreign_key: :actor_id, dependent: :nullify
  has_many :comments, dependent: :destroy
  has_many :communities
  has_many :conversation_participants, dependent: :destroy
  has_many :conversations, through: :conversation_participants
  has_many :external_identities, dependent: :destroy
  has_many :identity_assurances, dependent: :destroy
  has_many :marketplace_favorites, class_name: "Marketplace::ListingFavorite", dependent: :destroy
  has_many :marketplace_listings, class_name: "Marketplace::Listing", dependent: :destroy
  has_many :marketplace_orders, class_name: "Marketplace::Order", foreign_key: :buyer_id, dependent: :destroy
  has_many :marketplace_saved_searches, class_name: "Marketplace::SavedSearch", dependent: :destroy
  has_many :moderation_flags, dependent: :destroy
  has_many :moderation_reports, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :playlist_listens, class_name: "Playlist::Listen", dependent: :destroy
  has_many :playlist_playlists, class_name: "Playlist::Playlist", dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :reputation_scores, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :takeaway_favorite_restaurants, class_name: "Takeaway::FavoriteRestaurant", dependent: :destroy
  has_many :takeaway_orders, class_name: "Takeaway::Order", dependent: :destroy
  has_many :takeaway_restaurants, class_name: "Takeaway::Restaurant", dependent: :destroy
  has_many :trust_signals, dependent: :destroy
  has_many :tv_channels, class_name: "Tv::Channel", dependent: :destroy
  has_many :tv_subscriptions, class_name: "Tv::Subscription", dependent: :destroy
  has_many :votes, dependent: :destroy

  has_many :dating_dislikes, class_name: "Dating::Dislike", foreign_key: :disliker_id, dependent: :destroy
  has_many :dating_likes, class_name: "Dating::Like", foreign_key: :liker_id, dependent: :destroy
  has_many :dating_matches_as_initiator, class_name: "Dating::Match", foreign_key: :initiator_id, dependent: :destroy
  has_many :dating_matches_as_receiver, class_name: "Dating::Match", foreign_key: :receiver_id, dependent: :destroy
  has_many :follows_as_followed, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :followers, through: :follows_as_followed, source: :follower
  has_many :following, through: :follows_as_follower, source: :followed
  has_many :subscribed_channels, through: :tv_subscriptions, source: :tv_channel

  has_one :dating_profile, class_name: "Dating::Profile", dependent: :destroy

  validates :email_address, presence: true, uniqueness: true
  validates :username, uniqueness: true, allow_nil: true

  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }

  include Shared::GeoLocatable

  def display_name = guest? ? "anon" : (username.presence || email_address.split("@").first)


  def anon_handle = "Stranger ##{Digest::SHA1.hexdigest(id.to_s)[0, 4].upcase}"

  def assured?(level)
    identity_assurances.where(level: level).where("expires_at IS NULL OR expires_at > ?", Time.current).exists?
  end

  def follow!(other)
    return if other == self

    follows_as_follower.find_or_create_by!(followed: other)
  end

  def following?(other) = follows_as_follower.exists?(followed: other)

  def timeline_posts
    Post.where(user: [ self ] + following).order(created_at: :desc)
  end

  def unfollow!(other)
    follows_as_follower.find_by(followed: other)&.destroy
  end

  def update_karma!
    score = Vote.joins("JOIN posts ON posts.id = votes.votable_id AND votes.votable_type = 'Post'")
                .where(posts: { user_id: id }).sum(:value)
    score += Vote.joins("JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
                 .where(comments: { user_id: id }).sum(:value)
    update_column(:karma, score)
  end
end
