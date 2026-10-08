# frozen_string_literal: true

# A public question on a listing, and the seller's answer to it.
#
# Public because a question is worth more to the buyers who never asked it than
# to the one who did: the private-offer thread answered the same thing once per
# buyer, and the answer left with them.
class Marketplace::Question < ApplicationRecord
  include Shared::Notifiable
  include Shared::StrictSafeAssociations

  belongs_to :listing, class_name: "Marketplace::Listing"
  belongs_to :user
  belongs_to :answered_by, class_name: "User", optional: true

  validates :body, presence: true, length: { maximum: 1_000 }
  validates :answer, length: { maximum: 2_000 }

  scope :answered, -> { where.not(answered_at: nil) }
  scope :unanswered, -> { where(answered_at: nil) }
  # Answered first, because an answered question is the thing a reader came for;
  # newest within each half.
  scope :for_display, -> { order(Arel.sql("answered_at IS NULL, created_at DESC")) }

  def answered? = answered_at.present?

  def ask!
    return false unless save

    # kind "alert": the seller asked for nothing, but a question on their own
    # listing is exactly the thing they are waiting on, which is what a push is
    # for. See Notification::PUSHABLE_KINDS.
    # By id, not listing.user: the listing here is usually the one the request
    # already loaded, and walking a second association off a strict-loaded
    # record raises after the question has been written.
    deliver_notification(User.find_by(id: strict_safe_attribute(:listing, :user_id)),
      title: I18n.t("marketplace.question_notification_title"),
      body: body.to_s.truncate(120), source: self, kind: "alert")
    true
  end

  def answer!(text, by:)
    return false unless update(answer: text, answered_by: by, answered_at: Time.current)

    deliver_notification(strict_safe(:user),
      title: I18n.t("marketplace.answer_notification_title"),
      body: text.to_s.truncate(120), source: self, kind: "alert")
    true
  end

  # The seller answers. A store's listing is answered by whoever owns the store,
  # which is the same person today and need not stay that way.
  def answerable_by?(candidate)
    return false if candidate.blank?

    listing_record = strict_safe(:listing)
    return false if listing_record.blank?

    candidate.id == listing_record.user_id
  end
end
