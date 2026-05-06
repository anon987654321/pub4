class User < ApplicationRecord
  has_secure_password
  has_many :marketplace_listings, class_name: 'Marketplace::Listing', dependent: :destroy
  has_many :marketplace_orders,   class_name: 'Marketplace::Order',   foreign_key: :buyer_id, dependent: :destroy
  has_many :takeaway_restaurants, class_name: 'Takeaway::Restaurant', dependent: :destroy
  has_many :takeaway_orders,      class_name: 'Takeaway::Order',      dependent: :destroy
  has_many :playlist_playlists, class_name: 'Playlist::Playlist', dependent: :destroy
  has_many :playlist_listens,   class_name: 'Playlist::Listen',   dependent: :destroy
  has_one  :dating_profile,              class_name: 'Dating::Profile',  dependent: :destroy
  has_many :dating_likes,                class_name: 'Dating::Like',     foreign_key: :liker_id,    dependent: :destroy
  has_many :dating_dislikes,             class_name: 'Dating::Dislike',  foreign_key: :disliker_id, dependent: :destroy
  has_many :dating_matches_as_initiator, class_name: 'Dating::Match',    foreign_key: :initiator_id, dependent: :destroy
  has_many :dating_matches_as_receiver,  class_name: 'Dating::Match',    foreign_key: :receiver_id,  dependent: :destroy
  has_many :tv_channels,      class_name: "Tv::Channel",      dependent: :destroy
  has_many :tv_subscriptions, class_name: "Tv::Subscription", dependent: :destroy
  has_many :subscribed_channels, through: :tv_subscriptions, source: :tv_channel

  has_many :sessions, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :communities

  # Voting
  has_many :votes, dependent: :destroy

  # Social follows
  has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
  has_many :follows_as_followed, class_name: "Follow", foreign_key: :followed_id, dependent: :destroy
  has_many :following, through: :follows_as_follower, source: :followed
  has_many :followers,  through: :follows_as_followed, source: :follower

  # Messaging
  has_many :conversation_participants, dependent: :destroy
  has_many :conversations, through: :conversation_participants

  validates :email_address, presence: true, uniqueness: true
  validates :username, uniqueness: true, allow_nil: true
  normalizes :email_address, with: ->(e) { e.strip.downcase }

  def follow!(other)
    follows_as_follower.find_or_create_by!(followed: other) unless other == self
  end

  def unfollow!(other)
    follows_as_follower.find_by(followed: other)&.destroy
  end

  def following?(other) = follows_as_follower.exists?(followed: other)

  def timeline_posts
    Post.where(user: [self] + following).order(created_at: :desc)
  end

  def update_karma!
    k  = Vote.joins("JOIN posts    ON posts.id    = votes.votable_id AND votes.votable_type = 'Post'")
             .where(posts: { user_id: id }).sum(:value)
    k += Vote.joins("JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
             .where(comments: { user_id: id }).sum(:value)
    update_column(:karma, k)
  end
end
