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
      tags = names.map { |name| find_or_create_hashtag(name) }
      previous = hashtags.to_a
      # This line is Tagging's only writer, and it never names the class. A
      # census of models nothing writes reported Tagging as unwritten for that
      # reason — a grep for `Tagging.` or `taggings.create` finds readers only.
      self.hashtags = tags
      # usage_count is the number of records using the tag, so only move it by the
      # delta — a no-op edit changes nothing, and untagging decrements. The old
      # code incremented on every after_save, inflating counts on each edit.
      (tags - previous).each { |h| h.increment!(:usage_count) }
      (previous - tags).each { |h| h.decrement!(:usage_count) }
    end

    # find_or_create_by! is two statements with a gap between them, and name
    # carries a unique index. Two people posting the same tag in the same
    # instant lose the race, and the loser raises RecordNotUnique out of an
    # after_save, which rolls their post back. The retry reads what the other
    # one just wrote.
    def find_or_create_hashtag(name)
      Hashtag.find_or_create_by!(name:)
    rescue ActiveRecord::RecordNotUnique
      Hashtag.find_by!(name:)
    end
  end
end
