# frozen_string_literal: true

# Promoted to shared to reduce duplication and centralize (part of engine prep + sprawl reduction).
module Shared
  module Taggable
    extend ActiveSupport::Concern

    included do
      has_many :taggings, as: :taggable, dependent: :destroy, strict_loading: false, inverse_of: :taggable
      has_many :hashtags, through: :taggings, strict_loading: false
      after_save :sync_hashtags
    end

    def hashtag_list = hashtags.pluck(:name).join(" ")

    private

    def sync_hashtags
      names = Hashtag.extract(try(:content).to_s + " " + try(:title).to_s)
      tags = names.map { |n| Hashtag.find_or_create_by!(name: n) }
      previous = hashtags.to_a
      self.hashtags = tags
      # usage_count is the number of records using the tag, so only move it by the
      # delta — a no-op edit changes nothing, and untagging decrements. The old
      # code incremented on every after_save, inflating counts on each edit.
      (tags - previous).each { |h| h.increment!(:usage_count) }
      (previous - tags).each { |h| h.decrement!(:usage_count) }
    end
  end
end
