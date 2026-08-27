# frozen_string_literal: true

class Post < ApplicationRecord
  include Shared::Commentable

  belongs_to :user
  belongs_to :outfit, optional: true, touch: true
  belongs_to :item, optional: true, touch: true

  include Shared::RichTextLength

  # body holds Tiptap's HTML. presence still works — the editor writes "" when
  # it is empty rather than "<p></p>" — but the limit has to measure the text,
  # or "<p>" and "</p>" spend seven of the writer's 500 characters.
  validates :body, presence: true
  validates_rich_text_length :body, maximum: 500

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
