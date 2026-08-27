# frozen_string_literal: true

class User < ApplicationRecord

  # Vipps Login is the identity dating trusts. ExternalIdentity/IdentityProvider
  # already carry it — the callback writes one per successful OAuth round trip —
  # so this asks a question of existing data rather than adding a column that
  # would then need keeping in step with it.
  has_many :external_identities, dependent: :destroy

# Who may appear in the people picker. Guests have no stable identity to hold a
# conversation open, bots are addressed in their channel rather than privately,
# and a scheduled-for-deletion account should not collect new threads.
scope :messageable, -> { where(guest: false, bot: false, deleted_at: nil, deletion_scheduled_at: nil) }

  def vipps_verified?
    return false unless defined?(::ExternalIdentity) && defined?(::IdentityProvider)

    external_identities.joins(:identity_provider)
                       .where(identity_providers: { slug: "vipps" }).exists?
  end

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
  # The local side of an ActivityPub actor: identity is scoped to the user's
  # city domain, because that is already how brgen is partitioned.
  include Federatable

  has_secure_password

  validates :email_address, presence: true, uniqueness: true
  validates :username, uniqueness: true, allow_nil: true

  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }

  include Shared::GeoLocatable

  # Public profile pages a crawler may list. Not a tenant row — city_id is
  # only a home-city hint — so the sitemap names the city at the call site.
  scope :public_profiles, -> {
    where(guest: false).where.not(username: [ nil, "" ])
  }

  # The same name every city-facing surface uses, with the one difference this
  # model's shape forces: strict, not CityScoped.
  #
  # CityScoped reads a nil city_id as global — legal for a tenanted row, and it
  # belongs in every city rather than none. Here nil is the common case, not the
  # exception: guests are created in resume_session before set_domain_context
  # sets the tenant, so most rows carry no city at all. Treating those as global
  # would put every city's people on every city's sitemap, which is the leak
  # this scope exists to stop. No tenant means no rows, for the same reason.
  scope :in_current_city, -> {
    tenant = ActsAsTenant.current_tenant
    next none unless tenant

    where(city_id: tenant.id)
  }

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

  # Posts by people you follow, plus posts they reposted. A repost that only
  # showed on the reposter's profile would be a bookmark with extra steps — the
  # whole point is that it reaches the followers.
  def timeline_posts
    author_ids = [ id ] + following.ids
    Post.where(user_id: author_ids)
        .or(Post.where(id: Repost.where(user_id: author_ids).select(:post_id)))
        .order(created_at: :desc)
  end

  def unfollow!(other)
    follows_as_follower.find_by(followed: other)&.destroy
  end

  has_many :blocks_as_blocker, class_name: "Block", foreign_key: :blocker_id, dependent: :destroy
  has_many :blocked_users, through: :blocks_as_blocker, source: :blocked

  def block!(other)
    return if other == self

    blocks_as_blocker.find_or_create_by!(blocked: other)
  end

  def unblock!(other) = blocks_as_blocker.find_by(blocked: other)&.destroy
  def blocking?(other) = blocks_as_blocker.exists?(blocked_id: other.id)
  def blocked_user_ids = blocks_as_blocker.pluck(:blocked_id)

  has_many :community_memberships, dependent: :destroy
  has_many :joined_communities, through: :community_memberships, source: :community

  def join_community!(community)
    community_memberships.find_or_create_by!(community: community)
  end

  def leave_community!(community) = community_memberships.find_by(community: community)&.destroy
  def member_of?(community) = community_memberships.exists?(community_id: community.id)

  has_many :bookmarks, dependent: :destroy
  has_many :bookmarked_posts, through: :bookmarks, source: :post

  def bookmark!(post) = bookmarks.find_or_create_by!(post: post)
  def unbookmark!(post) = bookmarks.find_by(post: post)&.destroy
  def bookmarked?(post) = bookmarks.exists?(post_id: post.id)

  # Only accounts created through the public signup form need to confirm — that's
  # the impersonation vector. Programmatic users (seeds, tests, the IRC bridge,
  # guests) are trusted and grandfathered verified on create. UsersController#create
  # sets require_email_verification to opt a real signup into the gate.
  attr_accessor :require_email_verification
  before_create :grant_email_verification, unless: :require_email_verification

  def email_verified? = has_attribute?(:email_verified_at) ? email_verified_at.present? : true

  def generate_email_verification!
    token = SecureRandom.urlsafe_base64(32)
    update_columns(email_verification_token: token, updated_at: Time.current)
    token
  end

  def verify_email!
    update_columns(email_verified_at: Time.current, email_verification_token: nil, updated_at: Time.current)
  end

  def grant_email_verification
    self.email_verified_at ||= Time.current if has_attribute?(:email_verified_at)
  end

  # The subscribe-loop feed: hot posts from every community you've joined.
  def community_feed
    Post.hot.where(community_id: community_memberships.select(:community_id))
  end

  def update_karma!
    score = Vote.joins("JOIN posts ON posts.id = votes.votable_id AND votes.votable_type = 'Post'")
                .where(posts: { user_id: id }).sum(:value)
    score += Vote.joins("JOIN comments ON comments.id = votes.votable_id AND votes.votable_type = 'Comment'")
                 .where(comments: { user_id: id }).sum(:value)
    # updated_at with it: karma renders on the profile and on every post byline,
    # and update_column skips the timestamp, so `cache [user, ...]` fragments kept
    # serving the old score indefinitely -- the runner shows the new value and the
    # page shows the old one. The two methods above already do this; this was the
    # one that did not.
    update_columns(karma: score, updated_at: Time.current)
  end
end
