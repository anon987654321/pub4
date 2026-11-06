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
  validate  :price_kroner_is_an_amount

  before_validation :inherit_place_location
  after_update_commit :notify_attendees_of_change, if: :attendee_facing_change?

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
  # The index's strip of finished events. events/_event reads each card's
  # cover and neighbourhood, which strict loading refuses to fetch per card.
  def self.past_strip
    cards = past.includes(:user, :neighborhood)
    cards.with_attached_cover.limit(6)
  end
  scope :search, ->(q) {
    needle = "%#{sanitize_sql_like(q.to_s)}%"
    where("title LIKE :q OR description LIKE :q OR venue_name LIKE :q", q: needle)
  }

  def cancelled? = status == "cancelled"

  # A cancelled event stays readable: the cancellation notice links to it, and
  # its calendar file has to say CANCELLED to the people who imported it.
  # Only a draft is the organiser's alone.
  def readable_by?(user)
    status != "draft" || (user.present? && user.id == user_id)
  end
  def free? = price_cents.to_i.zero?

  # Organisers type kroner ("150" or "150,50"); the column keeps øre. Asking
  # for øre made 150 kr a 15000 to type with step 100, and one zero short sold
  # the ticket for 15 kr. What was typed is kept for the form when it fails.
  def price_kroner
    return @price_kroner_text if defined?(@price_kroner_text)
    return if price_cents.nil?

    whole, ore = price_cents.divmod(100)
    ore.zero? ? whole.to_s : format("%d%s%02d", whole, I18n.t("number.format.separator", default: ","), ore)
  end

  def price_kroner=(value)
    @price_kroner_text = value.to_s.strip
    amount = self.class.kroner_amount(@price_kroner_text)
    self.price_cents = amount.is_a?(BigDecimal) ? (amount * 100).round.to_i : nil
  end

  # "1 500,50", "1500.5", "150" -> a decimal; "" -> nil; anything else -> :invalid.
  def self.kroner_amount(text)
    plain = text.to_s.gsub(/[[:space:]]/, "").sub(",", ".")
    return if plain.empty?
    return :invalid unless plain.match?(/\A\d+(?:\.\d{1,2})?\z/)

    BigDecimal(plain)
  end

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

  # The names the event page lists under "N going"; going_count says how many
  # more there are.
  ATTENDEE_PREVIEW = 24
  def attendee_preview
    going = rsvps.going
    going.includes(:user).limit(ATTENDEE_PREVIEW)
  end

  def cancel!
    update!(status: "cancelled", cancelled_at: Time.current)
    notify_attendees_of_cancellation
  end

  private

  def price_kroner_is_an_amount
    return unless defined?(@price_kroner_text) && self.class.kroner_amount(@price_kroner_text) == :invalid

    errors.add(:price_kroner, :not_a_number)
  end

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

  # When, until when and where: the three things an attendee planned around.
  ATTENDEE_FACING_COLUMNS = %w[starts_at ends_at venue_name place_id].freeze

  def attendee_facing_change?
    !cancelled? && saved_changes.keys.intersect?(ATTENDEE_FACING_COLUMNS)
  end

  # A new time or venue reaches everyone who said they were coming, the way a
  # cancellation does; the organiser, who made the change, is not told.
  def notify_attendees_of_change
    body = I18n.t("events.changed_body", when: I18n.l(starts_at, format: :long), where: venue_name.presence || "–")
    others = rsvps.where.not(user_id:)
    coming = others.where(status: %w[going interested])
    coming.includes(:user).find_each do |rsvp|
      deliver_notification(rsvp.user, title: I18n.t("events.changed_notification", title:), body:,
                                      source: self, kind: "alert")
    end
  end

  # Everyone who said they were coming needs telling when it is called off.
  def notify_attendees_of_cancellation
    rsvps.where(status: %w[going interested]).includes(:user).find_each do |rsvp|
      deliver_notification(
        rsvp.user,
        title: I18n.t("events.cancelled_notification", title: title),
        body: I18n.t("events.cancelled_body"),
        source: self,
        # Someone who said they were coming has it in their calendar; a
        # cancellation they find out about on arrival is the failure this
        # notification exists to prevent.
        kind: "alert"
      )
    end
  end
end
