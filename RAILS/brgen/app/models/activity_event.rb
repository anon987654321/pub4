# frozen_string_literal: true

class ActivityEvent < ApplicationRecord
  belongs_to :actor, class_name: "User", optional: true

  # The polymorphic subject, when a batch loader has already fetched it.
  # subject_type/subject_id are not a Rails polymorphic association, so nothing
  # memoises the lookup: for_city_home resolved each subject to decide the city
  # and activity_event_href then resolved the same row again to build the link.
  # Carrying it on the instance makes the strip cost one query per type total.
  attr_accessor :activity_subject

  validates :source_vertical, :event_name, :subject_type, :subject_id, presence: true

  scope :visible, -> { where(moderation_state: "clean") }
  scope :recent, -> { order(created_at: :desc) }
  # Never surface private activity on a public profile (dating likes are private).
  scope :public_only, -> { where(visibility: "public") }

  # Public vertical births for the city-home strip. Posts stay on the feed;
  # this is interconnection, not a second timeline.
  HOME_STRIP_EVENTS = %w[
    ListingCreated
    TakeawayRestaurantCreated
    MarketplaceStoreCreated
    MarketplaceDealCreated
    VideoPublished
    EventCreated
  ].freeze

  def self.for_city_home(city, limit: 8)
    return none unless city

    candidates = visible.public_only.where(event_name: HOME_STRIP_EVENTS).recent.limit(limit * 4).to_a
    subjects = subjects_for(candidates)
    candidates.each { |event| event.activity_subject = subjects[[ event.subject_type.to_s, event.subject_id ]] }
    candidates.select { |event| in_city?(event, city, subjects) }.first(limit)
  end

  # One query per subject_type instead of one per event. in_city? loads the
  # subject whenever an event carries no matching locality, and this strip reads
  # limit * 4 events, so the city home page paid up to that many single-row
  # lookups — 12 against takeaway_restaurants alone, which is what
  # query_budget_test measured. :channel and :listing are preloaded because
  # in_city? walks them for the two models with no city_id of their own.
  def self.subjects_for(events)
    events.group_by(&:subject_type).each_with_object({}) do |(type, group), out|
      klass = type.to_s.safe_constantize
      next unless klass.respond_to?(:where)

      preload = %i[channel listing].select { |name| klass.reflect_on_association(name) }
      scope = preload.any? ? klass.includes(*preload) : klass
      scope.where(id: group.map(&:subject_id)).each { |record| out[[ type.to_s, record.id ]] = record }
    rescue StandardError
      next
    end
  end

  def self.in_city?(event, city, subjects = nil)
    labels = [ city.try(:name), city.try(:domain) ].compact
    if event.locality.present? && labels.any? { |label| event.locality.to_s.casecmp?(label.to_s) }
      return true
    end

    record = if subjects
               subjects[[ event.subject_type.to_s, event.subject_id ]]
    else
               event.subject_type.to_s.safe_constantize&.find_by(id: event.subject_id)
    end
    return false unless record

    city_id = record.try(:city_id)
    city_id = record.try(:channel).try(:city_id) if city_id.blank?
    city_id = record.try(:listing).try(:city_id) if city_id.blank?
    return city_id == city.id if city_id.present?

    event.locality.blank?
  end
end
