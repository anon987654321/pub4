```ruby
class Retweet < ApplicationRecord
  belongs_to :user
  belongs_to :retweetable, polymorphic: true

  validates :user_id, uniqueness: { scope: [:retweetable_type, :retweetable_id] }
  validates :retweetable_id, presence: true
  validates :retweetable_type, presence: true
  validate :cannot_retweet_own_content

  after_create :enqueue_retweet_notification
  after_destroy :cleanup_notifications

  def with_comment?
    comment.present?
  end

  private

  def cannot_retweet_own_content
    return unless retweetable
    if user_id == retweetable.user_id
      errors.add(:base, "Cannot retweet your own content")
    end
  end

  def enqueue_retweet_notification
    return if user_id == retweetable.user_id
    NotificationJob.perform_later('retweet', retweetable.user_id, self)
  end

  def cleanup_notifications
    Notification.where(notifiable: self).delete_all
  end
end

class Hashtag < ApplicationRecord
  has_many :taggings, dependent: :destroy

  validates :name, presence: true, uniqueness: true,
            format: { with: /\A[\p{Alnum}_]+\z/, message: "only allows letters, numbers and underscores" },
            length: { maximum: 50 }

  before_validation :normalize_name, if: :name_present?

  def self.find_or_create_by_name(name)
    normalized = name.downcase.strip
    return nil if normalized.blank?

    find_or_create_by(name: normalized)
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create hashtag #{normalized}: #{e.message}"
    nil
  end

  private

  def name_present?
    name.present?
  end

  def normalize_name
    self.name = name.downcase.strip
  end
end

class Mention < ApplicationRecord
  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_user, class_name: 'User'

  validates :mentioned_user_id, presence: true
  validates :mentionable_id, presence: true
  validates :mentionable_type, presence: true

  after_create_commit :enqueue_mention_notification

  private

  def enqueue_mention_notification
    NotificationJob.perform_later('mention', mentioned_user_id, self)
  end
end
```
