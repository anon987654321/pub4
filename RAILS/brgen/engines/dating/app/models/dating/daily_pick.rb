# frozen_string_literal: true

# A short list for today, instead of a deck with no bottom.
#
# Rows rather than a computed slice, because the point of a daily list is that
# it is the same list all day — a recomputed one shifts under the reader as
# people come online, which is the deck's behaviour and the thing this is meant
# to be a break from.
# model_contract: no-validations-ok — the (user, profile, day) key is enforced
# by the database and must stay there: for_today races two tabs on purpose and
# rescues RecordNotUnique, which a uniqueness validation would turn into a
# RecordInvalid the rescue does not catch.
class Dating::DailyPick < ApplicationRecord
  PER_DAY = 5

  belongs_to :user, class_name: "User"
  belongs_to :profile, class_name: "Dating::Profile"

  scope :for_day, ->(day = Date.current) { where(picked_on: day) }

  # Today's list, drawn once. Excludes anyone already picked this week, so the
  # same five faces do not come back every morning, and anyone already liked or
  # passed on, because a pick you have answered is not a pick.
  def self.for_today(viewer, scope:, day: Date.current)
    existing = where(user_id: viewer.id, picked_on: day)
               .includes(profile: [ :user, { photos_attachments: :blob } ]).map(&:profile)
    return existing if existing.any?

    recent = where(user_id: viewer.id, picked_on: (day - 6)..day).pluck(:profile_id)
    chosen = scope.where.not(id: recent).limit(PER_DAY).to_a
    chosen.each do |profile|
      create!(user_id: viewer.id, profile_id: profile.id, picked_on: day)
    rescue ActiveRecord::RecordNotUnique
      # Two tabs opened the page at the same second; the row that exists wins.
      nil
    end
    chosen
  end
end
