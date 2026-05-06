class User < ApplicationRecord
  has_secure_password
has_many :posts,    dependent: :destroy
has_many :items,    dependent: :destroy
has_many :outfits,  dependent: :destroy
has_many :planned_outfits, dependent: :destroy
has_many :follows_as_follower, class_name: "Follow", foreign_key: :follower_id, dependent: :destroy
has_many :follows_as_followee, class_name: "Follow", foreign_key: :followee_id, dependent: :destroy
has_many :following, through: :follows_as_follower, source: :followee
has_many :followers, through: :follows_as_followee, source: :follower
def following?(other) = follows_as_follower.exists?(followee: other)
def feed_posts = Post.where(user: [self] + following.to_a).recent
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
