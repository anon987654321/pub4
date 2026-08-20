# frozen_string_literal: true

class Post < ApplicationRecord
  include Shared::Commentable

  belongs_to :user
  belongs_to :outfit, optional: true, touch: true
  belongs_to :item, optional: true, touch: true

  validates :body, presence: true, length: { maximum: 500 }

  scope :recent, -> { order(created_at: :desc) }
  scope :anonymous, -> { where(anonymous: true) }
  scope :public_feed, -> { recent }

  def author_name
    return "anon" if anonymous? || user&.guest?

    user.display_name
  end

  def anonymous?
    has_attribute?(:anonymous) && self[:anonymous]
  end

  after_commit :broadcast_live_refresh

  def to_markdown
    body.to_s
  end

  def like! = increment!(:likes_count)

  private

  def broadcast_live_refresh
    broadcast_refresh_to "posts"
    broadcast_refresh_to self
  end
end
