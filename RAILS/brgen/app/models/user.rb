# frozen_string_literal: true

class User < ApplicationRecord
  include Shared::EmailVerification
  include Shared::Billable
  # Who may appear in the people picker. Guests have no stable identity to hold a
  # conversation open, bots are addressed in their channel rather than privately,
  # and a scheduled-for-deletion account should not collect new threads.
  scope :messageable, -> { where(guest: false, bot: false, deleted_at: nil, deletion_scheduled_at: nil) }
  # Shared a location at or after this time; nil (never shared) is not.
  scope :located_since, ->(time) { where(location_updated_at: time..) }

  # The "message me" token. A signed_id rather than a stored invite: nothing to
  # migrate, nothing to clean up, and it cannot be guessed or edited into someone
  # else's. It expires because a link shared once tends to outlive its reason.
  def message_invite_token
    signed_id(purpose: InvitesController::PURPOSE, expires_in: InvitesController::TTL)
  end

  # A Vipps Login or a BankID LOA 4 login has proved a real person: the
  # callback records either as assurance "verified" on its external identity.
  def identity_verified?
    return false unless defined?(::ExternalIdentity)

    external_identities.where(assurance_level: "verified").exists?
  end

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
  include User::NotificationPreferences
  # The local side of an ActivityPub actor: identity is scoped to the user's
  # city domain, because that is already how brgen is partitioned.
  include Federatable

  has_secure_password

  validates :email_address, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :username, uniqueness: true, allow_nil: true

  # What a person may choose as a username on the profile form: the characters
  # a mention can name (Mention.extract reads @[a-zA-Z0-9_]+), so every chosen
  # handle can be mentioned, at a length a profile header and an @-mention can
  # show. Held in the :profile context only, so seeds, bots and accounts made
  # before the rule keep saving; the form is where a name is chosen.
  # Also the form field's pattern attribute, so the browser holds the same rule.
  USERNAME_PATTERN = "[a-zA-Z0-9_]+"
  USERNAME_FORMAT = /\A#{USERNAME_PATTERN}\z/
  USERNAME_LENGTH = 3..30
  validates :username, presence: true, length: { in: USERNAME_LENGTH }, format: { with: USERNAME_FORMAT },
                       uniqueness: { case_sensitive: false }, on: :profile

  # Whether `name` is well formed and nobody else holds it in any letter case
  # (a mention matches case-insensitively).
  def username_available?(name)
    name = name.to_s
    return false unless User.username_well_formed?(name)

    !User.where.not(id:).exists?([ "LOWER(username) = ?", name.downcase ])
  end

  def self.username_well_formed?(name) = name.match?(USERNAME_FORMAT) && USERNAME_LENGTH.cover?(name.length)

  # A line or two under the name on the profile, not a second post.
  BIO_LENGTH = 160
  validates :bio, length: { maximum: BIO_LENGTH }

  # A photo the person chose, in place of the identicon. Shared::AttachmentLimits
  # holds it to image types and the image size limit, as an image slot.
  AVATAR_SIZE = 256
  has_one_attached :avatar do |attachable|
    attachable.variant :profile, resize_to_fill: [ AVATAR_SIZE, AVATAR_SIZE ]
  end

  normalizes :email_address, with: ->(email_address) { email_address.strip.downcase }

  include Shared::GeoLocatable

  # Public profile pages a crawler may list. Not a tenant row — city_id is
  # only a home-city hint — so the sitemap names the city at the call site.
  scope :public_profiles, -> {
    where(guest: false, deleted_at: nil, deletion_scheduled_at: nil)
      .where.not(username: [ nil, "" ])
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

  def anon_handle = I18n.t("chat.anon_handle", code: Digest::SHA1.hexdigest(id.to_s)[0, 4].upcase)

  # In public channels humans stay anonymous ("Fremmed #A1B2"); bots wear their
  # persona name so the room can tell an agent from a lurker.
  def channel_handle = bot? ? (username.presence || "bot") : anon_handle

  # BRGEN_OLD's per-user identicon (see AvatarsController). Callers that show
  # this alongside a genuinely anonymous name (Post#author_avatar_url,
  # channel messages) must not use it -- a consistent pattern would
  # re-identify the same "anon" across posts even though the name doesn't.
  #
  # The same address whether the person uploaded a photo or not, so no caller
  # needs the attachment loaded; AvatarsController answers with the photo when
  # there is one. The address carries updated_at because that answer is cached
  # for a year, and attaching or removing a photo touches the user.
  def avatar_url
    path = Rails.application.routes.url_helpers.avatar_user_path(self)
    updated_at ? "#{path}?v=#{updated_at.to_i}" : path
  end

  def assured?(level)
    identity_assurances.where(level: level).where("expires_at IS NULL OR expires_at > ?", Time.current).exists?
  end

  # Only what a profile may say this person wrote and `viewer` may read: no
  # anonymous or Live posts, nothing removed, no private community the viewer
  # is not in.
  def readable_posts_for(viewer)
    kept = posts.kept
    kept.attributed.visible_to(viewer)
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
    author_ids = [ id ] + follows_as_follower.pluck(:followed_id)
    Post.where(user_id: author_ids)
        .or(Post.where(id: Repost.where(user_id: author_ids).select(:post_id)))
        .order(created_at: :desc)
  end

  def unfollow!(other)
    follows_as_follower.find_by(followed: other)&.destroy
  end

  has_many :blocks_as_blocker, class_name: "Block", foreign_key: :blocker_id, dependent: :destroy, inverse_of: :blocker
  has_many :blocked_users, through: :blocks_as_blocker, source: :blocked

  # A block ends any follow between the two, both ways: left standing, the
  # blocked person still followed and was still notified.
  def block!(other)
    return if other == self

    transaction do
      Follow.where(follower: self, followed: other).or(Follow.where(follower: other, followed: self)).destroy_all
      blocks_as_blocker.create_or_find_by!(blocked: other)
    end
  end

  def unblock!(other) = blocks_as_blocker.find_by(blocked: other)&.destroy
  def blocking?(other) = blocks_as_blocker.exists?(blocked_id: other.id)
  def blocked_user_ids = blocks_as_blocker.pluck(:blocked_id)

  # The blocks the account page lists, newest first, each person loaded with it.
  # A blocked person can live in another city, so the lookup is not tenant-scoped.
  def blocks_for_review
    ActsAsTenant.without_tenant { blocks_as_blocker.includes(:blocked).order(created_at: :desc).to_a }
  end

  # People on neither side of a block with user, for lists that offer someone:
  # search results and the new-conversation picker.
  scope :unblocked_with, lambda { |user|
    where.not(id: Block.where(blocker_id: user.id).select(:blocked_id))
      .where.not(id: Block.where(blocked_id: user.id).select(:blocker_id))
  }

  has_many :share_drafts, dependent: :destroy
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

  # The subscribe-loop feed: hot posts from every community you've joined.
  def community_feed
    Post.hot.where(community_id: community_memberships.select(:community_id))
  end
end
