# frozen_string_literal: true

class User < ApplicationRecord
  # Deliberately NOT CityTenantable. A person is not a tenant row: email
  # uniqueness is global, one session follows a visitor across every city
  # domain, and stranger discovery is radius-based (Shared::GeoLocatable), not
  # city-based. Tenanting this model scoped every User read to
  # city_id = current_tenant, and no user row ever carried a city — guests are
  # created in resume_session, which runs before set_domain_context sets the
  # tenant, and seeds run outside a request. So every lookup returned nil:
  # post.user, message.sender and User.nearby all came back empty, which read
  # as "everything is anonymous" and 500'd anything that called a method on the
  # author. The city column stays as a home-city hint for the seeders.
  belongs_to :city, optional: true
  include User::CoreAssociations
  include User::MarketplaceAssociations
  include User::PlaylistAssociations
  include User::TakeawayAssociations
  include User::TvAssociations
  include User::DatingAssociations
  include User::SocialAssociations

  has_secure_password

  validates :email_address, presence: true, uniqueness: true
  validates :username, uniqueness: true, allow_nil: true

  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }

  include Shared::GeoLocatable

  # Never falls through to the email address. This method shadows the users
  # .display_name column, so the stored name was dead and every caller — the
  # marketplace seller line, dating matches, takeaway drivers, TV comments —
  # rendered the local part of a real person's email on a public page instead.
  # SSO provisioning writes that column; read it.
  def display_name = guest? ? "anon" : (self[:display_name].presence || username.presence || anon_handle)

  def anon_handle = "Stranger ##{Digest::SHA1.hexdigest(id.to_s)[0, 4].upcase}"

  # In public channels humans stay anonymous ("Stranger #A1B2"); bots wear their
  # persona name so the room can tell an agent from a lurker.
  def channel_handle = bot? ? (username.presence || "bot") : anon_handle

  # BRGEN_OLD's per-user identicon (see AvatarsController). Callers that show
  # this alongside a genuinely anonymous name (Post#author_avatar_url,
  # channel messages) must not use it -- a consistent pattern would
  # re-identify the same "anon" across posts even though the name doesn't.
  def avatar_url = Rails.application.routes.url_helpers.avatar_user_path(self)

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
