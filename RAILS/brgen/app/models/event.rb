# frozen_string_literal: true

# Something happening in the city, at a time, that people can say they are
# coming to.
#
# Location is deliberately two-sided: an event either points at a Place (a venue
# already on the map, with its own coordinates) or carries a free-text
# venue_name plus its own lat/lng. Requiring a Place would mean no one could
# post a party in their own flat, and requiring coordinates would mean no one
# could post one before the venue was settled.
class Event < ApplicationRecord
  include CityTenantable
  include Shared::Sluggable # /events/konsert-pa-landmark; unique per city
  include Shared::GeoLocatable
  include Shared::MediaProcessable
  include Shared::Commentable
  include Shared::Notifiable
  tracks_activity created: "EventCreated", updated: "EventUpdated", source_vertical: "social", actor: :user

  STATUSES = %w[draft published cancelled].freeze

  belongs_to :user
  belongs_to :place, optional: true
  belongs_to :neighborhood, optional: true

  has_many :rsvps, class_name: "EventRsvp", dependent: :destroy
  has_many :attendees, through: :rsvps, source: :user

  has_one_attached :cover
  process_media_variants :cover, variants: {
    card: { resize_to_limit: [ 800, 450 ], format: :webp },
    hero: { resize_to_limit: [ 1_600, 900 ], format: :webp }
  }

  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 20_000 }
  validates :starts_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :capacity, numericality: { greater_than: 0 }, allow_nil: true
  validate  :ends_after_it_starts

  before_validation :inherit_place_location

  scope :published, -> { where(status: "published") }
  # Upcoming means "has not finished", not "has not started": a three-day
  # festival is still upcoming on day two, and dropping it from the list at the
  # opening minute is how listings pages lie about what is on.
  scope :upcoming, lambda {
    published.where("COALESCE(events.ends_at, events.starts_at) >= ?", Time.current)
             .order(starts_at: :asc)
  }
  scope :past, lambda {
    published.where("COALESCE(events.ends_at, events.starts_at) < ?", Time.current)
             .order(starts_at: :desc)
  }
  scope :search, ->(q) { where("title LIKE :q OR description LIKE :q OR venue_name LIKE :q", q: "%#{q}%") }

  def cancelled? = status == "cancelled"
  def free? = price_cents.to_i.zero?
  def price_display = free? ? nil : Shared::MoneyDisplay.format(price_cents, currency)

  def location_name = venue_name.presence || strict_safe(:place)&.name

  def finished_at = ends_at.presence || starts_at
  def upcoming? = finished_at.present? && finished_at >= Time.current
  def in_progress? = starts_at <= Time.current && finished_at >= Time.current

  # nil when no capacity was set — "unlimited" is a real answer and must not
  # render as "0 places left".
  def places_left
    return nil if capacity.blank?

    [ capacity - going_count, 0 ].max
  end

  def full? = places_left&.zero? || false

  def rsvp_for(user) = user.present? ? rsvps.find_by(user_id: user.id) : nil

  def cancel!
    update!(status: "cancelled", cancelled_at: Time.current)
    notify_attendees_of_cancellation
  end

  private

  # A Place already carries verified coordinates and a name. Copying them at
  # validation keeps every event answerable on a map without making the form ask
  # twice, and without a join on every card.
  def inherit_place_location
    linked = place
    return if linked.blank?

    self.latitude   ||= linked.latitude
    self.longitude  ||= linked.longitude
    self.venue_name ||= linked.name
    self.neighborhood ||= linked.neighborhood
  end

  def ends_after_it_starts
    return if ends_at.blank? || starts_at.blank?
    return if ends_at >= starts_at

    errors.add(:ends_at, :before_start)
  end

  # Everyone who said they were coming needs telling, and this is the one place
  # an event can change under them.
  def notify_attendees_of_cancellation
    rsvps.where(status: %w[going interested]).includes(:user).find_each do |rsvp|
      deliver_notification(
        rsvp.user,
        title: I18n.t("events.cancelled_notification", title: title),
        body: I18n.t("events.cancelled_body"),
        source: self
      )
    end
  end
end
