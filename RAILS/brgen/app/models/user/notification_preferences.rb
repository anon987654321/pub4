# frozen_string_literal: true

# What the account page lets a person choose per kind of notification: a push
# to their devices, an email, both or neither. Unset choices keep the defaults:
# push on, as it always was, and email off, so no one starts receiving mail
# they never asked for.
module User::NotificationPreferences
  extend ActiveSupport::Concern

  CHOOSABLE_KINDS = %w[mention reply message follow].freeze
  CHANNELS = %w[push email].freeze
  DEFAULTS = { "push" => true, "email" => false }.freeze

  def notify_by?(channel, kind)
    channel = channel.to_s
    kind = kind.to_s
    return DEFAULTS.fetch(channel) unless CHOOSABLE_KINDS.include?(kind)

    chosen = notification_preferences.to_h.dig(kind, channel)
    chosen.nil? ? DEFAULTS.fetch(channel) : chosen
  end

  # From the account form's checkboxes: a kind and channel box sent as "1" is
  # on, anything else off. Every choosable pair is written, so a cleared box is
  # recorded as a choice rather than falling back to its default.
  def update_notification_preferences!(submitted)
    submitted = submitted.to_h
    choices = CHOOSABLE_KINDS.index_with do |kind|
      CHANNELS.index_with { |channel| submitted.dig(kind, channel).to_s == "1" }
    end
    update!(notification_preferences: choices)
  end
end
