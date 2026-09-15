# frozen_string_literal: true

# A business asking to be shown as verified, and the person who decides.
#
# Verified means a human compared the legal name and organisation number with
# Brønnøysundregistrene and found the account's owner speaks for that business.
# It is free, and nothing bought anywhere changes it: payment never buys a trust
# outcome (apps.yml, brgen monetization). The checksum below only refuses a
# number that cannot exist; the register lookup is the reviewer's.
class BusinessVerification < ApplicationRecord
  include Shared::Notifiable

  STATUSES = %w[pending verified rejected].freeze
  # Which column on each business names its owner. A business type is admitted
  # here or nowhere, so a request cannot point the verdict at an arbitrary table.
  OWNER_KEYS = { "Marketplace::Store" => :owner_id, "Takeaway::Restaurant" => :user_id }.freeze
  ORGANISATION_WEIGHTS = [ 3, 2, 7, 6, 5, 4, 3, 2 ].freeze

  belongs_to :business, polymorphic: true
  belongs_to :requested_by, class_name: "User"
  belongs_to :reviewed_by, class_name: "User", optional: true

  before_validation :normalise_organisation_number

  validates :business_type, inclusion: { in: OWNER_KEYS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :legal_name, presence: true, length: { maximum: 200 }
  validate :organisation_number_must_exist
  validate :requester_must_own_business, on: :create
  validate :one_pending_request_per_business, on: :create

  scope :pending, -> { where(status: "pending") }

  # The eight weights and the mod-11 rule are the register's own definition of
  # an organisasjonsnummer; a remainder that yields 10 is a number never issued.
  def self.organisation_number_valid?(number)
    digits = number.to_s.chars
    return false unless digits.size == 9 && digits.all? { |char| char.match?(/\d/) }

    sum = ORGANISATION_WEIGHTS.each_with_index.sum { |weight, index| weight * digits[index].to_i }
    check = (11 - (sum % 11)) % 11
    check != 10 && check == digits.last.to_i
  end

  def pending? = status == "pending"

  def approve!(by:, note: nil)
    decide!(status: "verified", by: by, note: note)
    notify(I18n.t("business_verifications.approved_title"), I18n.t("business_verifications.approved_body"))
  end

  def reject!(by:, note: nil)
    decide!(status: "rejected", by: by, note: note)
    notify(I18n.t("business_verifications.rejected_title"), note.presence || I18n.t("business_verifications.rejected_body"))
  end

  private

  # The verdict is written onto the business, because every card reads it and a
  # join per card is the shape that made feeds slow. unscoped, since the
  # reviewer's host picks the tenant and the business belongs to its own city;
  # updated_at moves so a cached card stops showing the old verdict.
  def decide!(status:, by:, note:)
    transaction do
      update!(status: status, reviewed_by: by, reviewed_at: Time.current, review_note: note.presence)
      business_scope.update_all(verified: status == "verified", updated_at: Time.current)
    end
  end

  def business_scope = business_type.constantize.unscoped.where(id: business_id)

  def notify(title, body)
    deliver_notification(User.find_by(id: requested_by_id), title: title, body: body, source: self, kind: "alert")
  end

  def normalise_organisation_number
    self.organisation_number = organisation_number.to_s.gsub(/\s/, "")
  end

  def organisation_number_must_exist
    errors.add(:organisation_number, :invalid) unless self.class.organisation_number_valid?(organisation_number)
  end

  def requester_must_own_business
    key = OWNER_KEYS[business_type]
    return if key.nil?

    owner_id = business_scope.pick(key)
    errors.add(:base, :not_owner) unless owner_id.present? && owner_id == requested_by_id
  end

  def one_pending_request_per_business
    return if business_id.blank?

    errors.add(:base, :already_pending) if self.class.pending.where(business_type: business_type, business_id: business_id).exists?
  end
end
