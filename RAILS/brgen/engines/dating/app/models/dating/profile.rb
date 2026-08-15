# frozen_string_literal: true

class Dating::Profile < ApplicationRecord
  include CityTenantable

  tracks_activity created: "DatingProfileCreated", updated: "DatingProfileUpdated", source_vertical: "dating", visibility: "private", actor: :user
  include Shared::GeoLocatable
  include Shared::MediaProcessable
  include Shared::Reactable
  belongs_to :user
  belongs_to :neighborhood, optional: true
  has_many_attached :photos
  process_media_variants :photos, variants: {
    thumb: { resize_to_limit: [ 400, 600 ], format: :webp },
    card: { resize_to_limit: [ 800, 1_200 ], format: :webp },
  }

  GENDERS     = %w[man woman nonbinary other].freeze
  LOOKING_FOR = %w[man woman everyone].freeze

  # Mutual orientation for discovery: show the viewer only the gender they're
  # looking for (unless "everyone"/blank), and only profiles who'd want the
  # viewer back. nil/"everyone" stay open on both sides, so nobody is filtered to
  # an empty deck by leaving a preference unset.
  scope :oriented_for, lambda { |viewer|
    relation = all
    relation = relation.where(gender: viewer.looking_for) if %w[man woman].include?(viewer&.looking_for)
    relation = relation.where(looking_for: [ viewer.gender, "everyone", nil ]) if viewer&.gender.present?
    relation
  }

  validates :bio,         length: { maximum: 500 }
  validates :age, numericality: { greater_than_or_equal_to: 18, less_than: 100 }
  validates :gender,      inclusion: { in: GENDERS },     allow_nil: true
  validates :looking_for, inclusion: { in: LOOKING_FOR }, allow_nil: true
  validate :photos_present_when_visible

  has_many :prompts, class_name: "Dating::Prompt", dependent: :destroy

  scope :visible, -> { where(visible: true).where("age >= 18") }
  # Visible-without-photos used to be creatable (the validation ran on :update
  # only) and then sat in the deck as a blank card. The attribute-named
  # `visible` scope stays the flag+age filter; deck surfaces add this.
  scope :with_photos, -> { joins(:photos_attachments).distinct }

  # The deck was ORDER BY RANDOM(). Orientation, neighbourhood and a 20 km
  # radius filtered the pool and nothing ranked it, so someone who last opened
  # this in March sat beside someone who is online now — and every reload
  # reshuffled, so a profile you had just seen could not be found again.
  #
  # Three ingredients, in this order:
  #
  #   recency  — who is actually around. A dating app whose deck is full of
  #              dormant accounts is a dating app nobody matches on.
  #   effort   — a profile with prompts answered gives the viewer something to
  #              reply to, which is the whole interaction this vertical is for.
  #   shuffle  — a per-viewer, per-day deterministic jitter. Without it the same
  #              profile is top of everyone's deck forever, and with plain
  #              RANDOM() the order changes on every reload.
  #
  # Deliberately not "attractiveness", engagement or any like-count feedback
  # loop: ranking people by how much attention they already get is how these
  # products end up with a handful of accounts receiving everything.
  RECENCY_SQL = <<~SQL.squish
    CASE
      WHEN dating_profiles.last_active_at IS NULL THEN 3
      WHEN dating_profiles.last_active_at > datetime('now', '-2 days')  THEN 0
      WHEN dating_profiles.last_active_at > datetime('now', '-14 days') THEN 1
      ELSE 2
    END
  SQL

  # A prime modulus with a per-viewer multiplier, not a per-viewer offset:
  # adding a constant to every id shifts all of them equally and leaves the
  # order unchanged, which is exactly what the first version of this did.
  # Multiplying by a different coprime genuinely permutes the deck.
  SHUFFLE_MODULUS = 997

  def self.ranked_for(viewer, seed: Date.current.to_s)
    multiplier = (Digest::MD5.hexdigest("#{seed}:#{viewer&.id}")[0, 6].to_i(16) % (SHUFFLE_MODULUS - 1)) + 1
    # Integer() rather than the bare local: both values are integers by
    # construction — to_i(16) % 996 + 1, and a literal constant — but Brakeman
    # cannot follow that through the digest and reported the interpolation as
    # possible SQL injection, which failed brgen's CI. Integer() is the
    # narrowest way to make it provable: it raises rather than coerces, so it
    # states the invariant instead of hiding a violation of it. ORDER BY cannot
    # take a bind parameter, so interpolation is the only shape available here.
    multiplier = Integer(multiplier)
    modulus = Integer(SHUFFLE_MODULUS)
    order(Arel.sql(<<~SQL.squish))
      #{RECENCY_SQL} ASC,
      (SELECT COUNT(*) FROM dating_prompts WHERE dating_prompts.profile_id = dating_profiles.id) DESC,
      ((dating_profiles.id * #{multiplier}) % #{modulus}) ASC
    SQL
  end

  # Distinct from updated_at, which changes when a photo variant is processed in
  # the background and would otherwise read as someone being around.
  def touch_activity!
    update_columns(last_active_at: Time.current, updated_at: Time.current)
  end
  # nearby (bbox) + haversine provided by concern; old approx replaced for consistency
  scope :in_neighborhood, ->(neigh) { neigh ? where(neighborhood_id: neigh.id) : all }

  def name = user.display_name

  def liked_by?(user)    = Dating::Like.exists?(liker: user, likee: self.user)
  def disliked_by?(user) = Dating::Dislike.exists?(disliker: user, dislikee: self.user)
  def matched_with?(user)
    Dating::Match.where(status: "matched")
      .where("(initiator_id = ? AND receiver_id = ?) OR (initiator_id = ? AND receiver_id = ?)",
             self.user_id, user.id, user.id, self.user_id).exists?
  end

  private

  def photos_present_when_visible
    return unless visible?
    return if photos.attached?

    errors.add(:photos, :required_when_visible)
  end
end
