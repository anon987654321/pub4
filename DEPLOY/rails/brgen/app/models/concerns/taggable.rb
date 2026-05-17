module Taggable
  extend ActiveSupport::Concern

  included do
    has_many :taggings, as: :taggable, dependent: :destroy
    has_many :hashtags, through: :taggings
    after_save :sync_hashtags
  end

  def hashtag_list = hashtags.pluck(:name).join(" ")

  private

  def sync_hashtags
    names = Hashtag.extract(try(:content).to_s + " " + try(:title).to_s)
    tags  = names.map { |n| Hashtag.find_or_create_by!(name: n).tap { |h| h.increment!(:usage_count) } }
    self.hashtags = tags
  end
end
