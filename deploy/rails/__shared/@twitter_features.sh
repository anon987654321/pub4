```ruby
class Retweet < ApplicationRecord
  belongs_to :user
  belongs_to :retweetable, polymorphic: true

  validates :user_id, uniqueness: { scope: [:retweetable_type, :retweetable_id] }
  validate :cannot_retweet_own_content

  after_create :notify_original_author
  after_destroy :remove_notification

  def with_comment?
    content.present?
  end

  private

  def cannot_retweet_own_content
    if user_id == retweetable.user_id
      errors.add(:base, "Cannot retweet your own content")
    end
  end

  def notify_original_author
    return if user_id == retweetable.user_id
    NotificationMailer.retweet(retweetable.user, self).deliver_later
  end

  def remove_notification
    Notification.where(notifiable: self).delete_all
  end
end

class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  validates :name, presence: true, uniqueness: true,
            format: { with: /\A[a-zA-Z0-9_]+\z/, message: "only allows letters, numbers and underscores" },
            length: { maximum: 50 }

  before_save :normalize_name

  def self.find_or_create_by_name(name)
    normalized = name.downcase.strip
    find_or_create_by(name: normalized) if normalized.present?
  end

  private

  def normalize_name
    return if name.blank?
    self.name = name.downcase.strip
  end
end

class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_user, class_name: 'User'

  after_create :notify_mentioned_user

  private

  def notify_mentioned_user
    NotificationMailer.mention(mentioned_user, self).deliver_later
  end
end

class Follow < ApplicationRecord
  belongs_to :follower, class_name: 'User'
  belongs_to :followed, class_name: 'User'

  validates :follower_id, exclusion: { in: ->(follow) { [follow.followed_id] }, message: "cannot follow yourself" }

  after_destroy :remove_follow_notification

  private

  def remove_follow_notification
    Notification.where(notifiable: self).delete_all
  end
end
```
