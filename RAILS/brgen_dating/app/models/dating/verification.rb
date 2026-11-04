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
    with_lock do
      raise ActiveRecord::RecordNotFound unless pending?

      reviewed_at = Time.current
      update!(status: "verified", reviewed_by: by, reviewed_at: reviewed_at, review_note: note.presence)
      # Denormalised onto the profile: every deck card reads it, and a join per
      # card is the shape that made this feed slow before.
      Dating::Profile.where(id: profile_id).update_all(verified_at: reviewed_at)
    end
    notify(I18n.t("dating.verification_approved_title"), I18n.t("dating.verification_approved_body"))
    record_trust_signal
  end

  def reject!(by:, note: nil)
    with_lock do
      raise ActiveRecord::RecordNotFound unless pending?

      update!(status: "rejected", reviewed_by: by, reviewed_at: Time.current, review_note: note.presence)
      Dating::Profile.where(id: profile_id).update_all(verified_at: nil)
      Dating::LocationPing.where(user_id: Dating::Profile.where(id: profile_id).pick(:user_id)).delete_all
    end
    notify(I18n.t("dating.verification_rejected_title"), note.presence || I18n.t("dating.verification_rejected_body"))
  end

  private

  def notify(title, body)
    owner = User.find_by(id: Dating::Profile.where(id: profile_id).pick(:user_id))
    deliver_notification(owner, title: title, body: body, source: self, kind: "alert")
  end

  # A reviewed photo match is evidence about the person, so it counts toward
  # their reputation as phone or BankID verification does. One signal per
  # approved request: the unique (user, kind, source) index holds a repeat.
  def record_trust_signal
    owner = User.find_by(id: Dating::Profile.where(id: profile_id).pick(:user_id))
    return unless owner

    kind = "dating_photo_verified"
    owner.trust_signals.create_or_find_by!(kind:, source: "dating_verification:#{id}") do |signal|
      signal.weight = TrustScore::SIGNAL_WEIGHTS.fetch(kind)
    end
    TrustScore.new(user: owner).call
  end

  def selfie_must_be_attached
    errors.add(:selfie, :blank) unless selfie.attached?
  end

  def one_pending_request_per_profile
    return if profile_id.blank?

    errors.add(:base, :already_pending) if self.class.pending.where(profile_id: profile_id).exists?
  end
end
