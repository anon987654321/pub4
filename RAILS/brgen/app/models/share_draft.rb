# frozen_string_literal: true

# Incoming PWA shares are private staging records, not public posts. A share only
# becomes a Post after its owner reviews it and explicitly publishes it.
class ShareDraft < ApplicationRecord
  MAX_IMAGES = 5
  MAX_MEDIA = MAX_IMAGES + 1
  LIFETIME = 24.hours

  belongs_to :user
  belongs_to :city

  has_many_attached :images
  has_one_attached :video

  validates :title, presence: true, length: { maximum: 300 }
  validates :content, length: { maximum: 40_000 }
  validate :within_media_count
  before_validation :set_expiry, on: :create

  scope :expired, -> { where(expires_at: ..Time.current) }

  private

  def set_expiry
    self.expires_at ||= LIFETIME.from_now
  end

  def within_media_count
    image_count = images.blobs.size
    errors.add(:images, "cannot contain more than #{MAX_IMAGES} files") if image_count > MAX_IMAGES
    errors.add(:base, "cannot contain more than #{MAX_MEDIA} media files") if image_count + (video.attached? ? 1 : 0) > MAX_MEDIA
  end
end
