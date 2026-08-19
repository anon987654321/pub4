# frozen_string_literal: true

# Days running that two people have answered each other's stories.
#
# Mutual on purpose: a streak that one person can hold up alone is a posting
# counter, and the thing it is meant to measure is a pair still talking. Both
# directions must have a reply on the same day for that day to count.
class StoryStreak < ApplicationRecord
  belongs_to :user_a, class_name: "User"
  belongs_to :user_b, class_name: "User"

  validates :days, numericality: { greater_than_or_equal_to: 0 }

  # The pair in id order, so a lookup never has to try both ways round and the
  # unique index can hold one row per pair.
  def self.pair_ids(a, b) = [ a.id, b.id ].minmax

  def self.for_pair(a, b)
    low, high = pair_ids(a, b)
    find_by(user_a_id: low, user_b_id: high)
  end

  # Called when a story reply lands. Counts the day only when the other person
  # has answered one of yours today too.
  def self.record_exchange!(sender, recipient, on: Date.current)
    return nil unless exchanged_on?(sender, recipient, on)

    low, high = pair_ids(sender, recipient)
    streak = find_or_create_by!(user_a_id: low, user_b_id: high)
    streak.advance!(on)
    streak
  end

  # Both directions, same day. Reads messages rather than a counter because the
  # counter is what this method exists to write: deriving it from a second
  # counter would be a number nobody could check against the thread.
  def self.exchanged_on?(sender, recipient, day)
    window = day.all_day
    [ [ sender, recipient ], [ recipient, sender ] ].all? do |from, to|
      Message.where(sender_id: from.id, created_at: window)
             .where.not(story_id: nil)
             .where(conversation_id: Conversation.for_user(to).select(:id))
             .exists?
    end
  end

  # { other_user_id => days }, live streaks only, for a page that draws a list of
  # people. One query rather than one per row.
  def self.days_by_other_user(user, on: Date.current)
    return {} if user.blank?

    where(user_a_id: user.id).or(where(user_b_id: user.id))
      .where(last_day: (on - 1)..)
      .pluck(:user_a_id, :user_b_id, :days)
      .to_h { |a, b, days| [ a == user.id ? b : a, days ] }
  end

  def advance!(day)
    return if last_day == day

    update!(days: last_day == day - 1 ? days + 1 : 1, last_day: day)
  end

  # A streak nobody kept up is over. Computed on read rather than swept: a job
  # that has not run yet would otherwise leave a dead streak on the page, and the
  # answer is one date comparison.
  def alive?(on: Date.current) = last_day.present? && last_day >= on - 1

  def display_days(on: Date.current) = alive?(on: on) ? days : 0
end
