# frozen_string_literal: true

# Proof that the person in the photos is the person holding the phone.
#
# A selfie in a pose the app picks, reviewed by a human. Not automatic: face
# matching is the kind of thing that fails on exactly the people it should not,
# and a wrong "not verified" on a dating profile is worse than a slow one.
class Dating::Verification < ApplicationRecord
  include Shared::Notifiable
  include Shared::StrictSafeAssociations

  STATUSES = %w[pending verified rejected].freeze
  # Drawn per request, and stored. Asking everybody for the same gesture makes a
  # single stolen photo enough to pass forever.
  POSES = %w[peace_sign hand_on_head thumbs_up palm_out point_up].freeze

  belongs_to :profile, class_name: "Dating::Profile"
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_one_attached :selfie

  validates :status, inclusion: { in: STATUSES }
  validates :pose, inclusion: { in: POSES }
  validate :selfie_must_be_attached
  validate :one_pending_request_per_profile, on: :create

  scope :pending, -> { where(status: "pending") }

  def self.pose_for_request = POSES.sample

  def pending? = status == "pending"

  def approve!(by:, note: nil)
    transaction do
      update!(status: "verified", reviewed_by: by, reviewed_at: Time.current, review_note: note.presence)
      # Denormalised onto the profile: every deck card reads it, and a join per
      # card is the shape that made this feed slow before.
      Dating::Profile.where(id: profile_id).update_all(verified_at: Time.current)
    end
    notify(I18n.t("dating.verification_approved_title"), I18n.t("dating.verification_approved_body"))
  end

  def reject!(by:, note: nil)
    transaction do
      update!(status: "rejected", reviewed_by: by, reviewed_at: Time.current, review_note: note.presence)
      Dating::Profile.where(id: profile_id).update_all(verified_at: nil)
    end
    notify(I18n.t("dating.verification_rejected_title"), note.presence || I18n.t("dating.verification_rejected_body"))
  end

  private

  def notify(title, body)
    owner = User.find_by(id: Dating::Profile.where(id: profile_id).pick(:user_id))
    deliver_notification(owner, title: title, body: body, source: self, kind: "alert")
  end

  def selfie_must_be_attached
    errors.add(:selfie, :blank) unless selfie.attached?
  end

  def one_pending_request_per_profile
    return if profile_id.blank?

    errors.add(:base, :already_pending) if self.class.pending.where(profile_id: profile_id).exists?
  end
end
