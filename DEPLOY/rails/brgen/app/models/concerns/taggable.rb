# frozen_string_literal: true

module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :hashtags, through: :taggings
    after_save :sync_hashtags
  end

    def hashtag_list
      hashtags.pluck(:name).join(" ")
    end

  private

  def sync_hashtags
    names = Hashtag.extract([try(:content), try(:title)].compact.join(" "))
    current_tags = hashtags.to_a
    tags = names.map { |name| Hashtag.find_or_create_by!(name: name) }

    (current_tags - tags).each { |tag| tag.decrement!(:usage_count) if tag.usage_count.to_i.positive? }
    (tags - current_tags).each { |tag| tag.increment!(:usage_count) }

    self.hashtags = tags
  end
end
