# frozen_string_literal: true

# A photo or clip that deletes itself.
#
# The lifetime is stored rather than computed from created_at, so a story's own
# row says when it goes — the sweep, the "expires in" label and the alive scope
# all read the same column instead of each re-deriving 24 hours from somewhere
# else and eventually disagreeing.
class Story < ApplicationRecord
  include CityTenantable
  include Shared::GeoLocatable
  include Shared::MediaProcessable
  include Shared::Notifiable

  LIFETIME = 24.hours
  # Same coarsening as Post's Live layer (~1 km): a story is often posted from
  # where you are standing, and exact GPS on a public surface is not something
  # to collect by default.
  LOCATION_PRECISION = 2

  belongs_to :user

  has_many :story_views, dependent: :destroy
  # Replies are messages in the pair's own DM thread, so they outlive the story:
  # :nullify, because the sweep takes the photo and not the conversation.
  has_many :replies, class_name: "Message", dependent: :nullify
  has_many :viewers, through: :story_views, source: :user

  has_one_attached :media
  process_media_variants :media, variants: {
    full: { resize_to_limit: [ 1_080, 1_920 ], format: :webp },
    thumb: { resize_to_limit: [ 240, 320 ], format: :webp }
  }

  validates :caption, length: { maximum: 280 }
  validate  :media_must_be_attached
  validate  :media_is_a_photo_or_clip, if: -> { attachment_changes.key?("media") }

  # Opt-in tagging of roughly where the author is. The position is the one
  # locations#update already stored — coarsened there to a ~1 km grid — rather
  # than a fresh GPS read from the compose form.
  attribute :attach_area, :boolean, default: false

  before_validation :set_expiry, on: :create
  before_validation :inherit_user_location, on: :create
  before_validation :coarsen_location

  scope :alive, -> { where("expires_at > ?", Time.current) }
  scope :newest_first, -> { order(created_at: :desc) }

  # Whose stories to show, in the order a reader wants them: people you follow,
  # then everyone else in the city. Grouped by author, because a story surface
  # is a list of people, not a list of photos.
  def self.rings_for(user, limit: 20)
    scope = alive.in_current_city.includes(:user).with_attached_media.newest_first
    grouped = scope.group_by(&:user_id)
    return grouped.values.first(limit) if user.blank?

    followed = user.follows_as_follower.pluck(:followed_id).to_set
    grouped.values.sort_by { |stories| followed.include?(stories.first.user_id) ? 0 : 1 }.first(limit)
  end

  def expired? = expires_at <= Time.current
  def expires_in = expired? ? 0 : (expires_at - Time.current).to_i

  def seen_by?(user) = user.present? && story_views.exists?(user_id: user.id)

  # Which of these stories the user has opened, in one query for the whole
  # ring list rather than one EXISTS per ring.
  def self.seen_ids(user, stories)
    return Set.new if user.blank?

    StoryView.where(user_id: user.id, story_id: stories.map(&:id)).pluck(:story_id).to_set
  end

  # Returns false rather than raising when the viewer has already seen it, so a
  # double-tap is not an error. Counting is a set, not a log.
  def view_by!(user)
    return false if user.blank? || user.id == user_id
    return false if story_views.exists?(user_id: user.id)

    # create_or_find_by! is wrong here: it rescues the database's uniqueness
    # error, and StoryView's model-level validation fires first, so a second
    # open raised RecordInvalid instead of reading as "already seen". The
    # rescue still covers the race the unique index is there for.
    begin
      story_views.create!(user: user)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      return false
    end

    # updated_at along with it: the ring is fragment-cached on [story], and a
    # view count that changes without it would render stale.
    update_columns(views_count: story_views.count, updated_at: Time.current)
    true
  end

  private

  def set_expiry
    self.expires_at ||= Time.current + LIFETIME
  end

  def inherit_user_location
    return unless attach_area
    return if latitude.present? && longitude.present?

    author = user
    return if author.blank? || author.latitude.blank?

    self.latitude = author.latitude
    self.longitude = author.longitude
  end

  def coarsen_location
    return if latitude.blank? || longitude.blank?

    self.latitude = latitude.to_f.round(LOCATION_PRECISION)
    self.longitude = longitude.to_f.round(LOCATION_PRECISION)
  end

  # A story with no media is not a story. Enforced here rather than left to the
  # view, because an empty ring is worse than a refused upload.
  def media_must_be_attached
    errors.add(:media, :blank) unless media.attached?
  end

  # To Shared::AttachmentLimits `media` is a mixed slot, held to size alone. A
  # story is a photo or a clip, so it takes those families at their own sizes.
  def media_is_a_photo_or_clip
    blob = media.blob
    kind = media_kind(blob.content_type.to_s.downcase)
    return errors.add(:media, :file_type_not_allowed) unless kind

    max = Shared::AttachmentLimits::KINDS.dig(kind, :max_bytes)
    errors.add(:media, :file_too_large, count: max / Shared::AttachmentLimits::MB) if blob.byte_size.to_i > max
  end

  def media_kind(type)
    return :image if Shared::AttachmentLimits::IMAGE_TYPES.include?(type)

    :video if type.start_with?("video/")
  end
end
