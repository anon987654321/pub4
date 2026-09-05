# frozen_string_literal: true

# One partner in one program, and the token every click carries.
#
# The token is generated once and never regenerated: it is embedded in links the
# partner has already posted, and rotating it silently orphans every click those
# links would have earned.
class Partner::Membership < ApplicationRecord
  self.table_name = "partner_memberships"

  belongs_to :program, class_name: "Partner::Program"
  belongs_to :user
  has_many :clicks, class_name: "Partner::Click", foreign_key: :membership_id, dependent: :destroy,
           inverse_of: :membership
  has_many :conversions, class_name: "Partner::Conversion", foreign_key: :membership_id,
           dependent: :restrict_with_error, inverse_of: :membership

  STATUSES = %w[pending approved rejected suspended].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :token, presence: true, uniqueness: true, length: { maximum: 32 }
  validates :user_id, uniqueness: { scope: :program_id }

  before_validation :assign_token, on: :create
  before_validation :auto_approve, on: :create

  scope :approved, -> { where(status: "approved") }

  # Only an approved partner in an open programme earns. Checked at click time
  # and again at attribution: a membership can be suspended between the two, and
  # the click that was legitimate when it happened must not pay out after.
  def earning? = status == "approved" && program.open?

  def approve!
    update!(status: "approved", approved_at: Time.current)
  end

  private

  def assign_token
    self.token ||= self.class.generate_token
  end

  def auto_approve
    return unless status.blank? || status == "pending"
    return unless program&.auto_approve_partners

    self.status = "approved"
    self.approved_at ||= Time.current
  end

  # Retry rather than trust one draw: the unique index is the real guarantee,
  # and a collision here should cost a second attempt, not a 500 for someone
  # signing up.
  def self.generate_token
    10.times do
      candidate = SecureRandom.alphanumeric(16).downcase
      return candidate unless exists?(token: candidate)
    end
    raise "could not generate a unique partner token"
  end
end
