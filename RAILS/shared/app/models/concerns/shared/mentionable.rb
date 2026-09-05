# frozen_string_literal: true

# Writes Mention rows from @username in title and content, the same way
# Shared::Taggable writes taggings from #tags. Post already had the
# association; nothing filled it.
module Shared
  module Mentionable
    extend ActiveSupport::Concern

    def self.backed?
      Object.const_defined?(:Mention)
    end

    included do
      if Shared::Mentionable.backed?
        has_many :mentions, as: :mentionable, dependent: :destroy,
                            inverse_of: :mentionable, strict_loading: false
        has_many :mentioned_users, through: :mentions, source: :mentioned_user,
                                   strict_loading: false
        after_save :sync_mentions, if: :mention_text_changed?
      end
    end

    private

    def mention_text_changed?
      (has_attribute?(:title) && saved_change_to_title?) ||
        (has_attribute?(:content) && saved_change_to_content?)
    end

    def sync_mentions
      handles = Mention.extract("#{try(:content)} #{try(:title)}")
      users = resolve_mentioned_users(handles)
      previous_ids = mentions.map(&:mentioned_user_id)
      self.mentioned_users = users
      notify_new_mentions(users.reject { |u| previous_ids.include?(u.id) })
    end

    def resolve_mentioned_users(handles)
      return [] if handles.empty?

      User.where("LOWER(username) IN (?)", handles.map(&:downcase))
          .reject { |u| u.id == user_id }
    end

    def notify_new_mentions(users)
      return if users.empty?

      actor = User.find_by(id: user_id)
      users.each do |mentioned|
        Notification.create!(
          user: mentioned,
          actor: actor,
          kind: "mention",
          notifiable: self
        )
      end
    end
  end
end
