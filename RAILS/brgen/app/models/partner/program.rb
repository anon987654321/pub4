# frozen_string_literal: true

# A store's offer to the people who might sell for it.
#
# The rate is the whole contract. A partner decides for themselves whether it is
# worth their effort, and competes against every other partner inside it — which
# is why the merchant's cost per sale cannot drift above what they set here, no
# matter how much volume arrives.
class Partner::Program < ApplicationRecord
  include CityTenantable

  self.table_name = "partner_programs"

  belongs_to :store, class_name: "Marketplace::Store"
  has_many :memberships, class_name: "Partner::Membership", foreign_key: :program_id, dependent: :destroy,
           inverse_of: :program
  has_many :partners, through: :memberships, source: :user
  has_many :conversions, through: :memberships, source: :conversions

  STATUSES = %w[draft open paused closed].freeze
  # cpa_percent: basis points of the order value. cpa_flat and cpl: cents.
  COMMISSION_MODELS = %w[cpa_percent cpa_flat cpl].freeze

  # A percentage commission above this is either a typo or a business that will
  # not survive the month, and both are worth refusing at the boundary.
  MAX_PERCENT_BPS = 5_000

  validates :name, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES }
  validates :commission_model, inclusion: { in: COMMISSION_MODELS }
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :attribution_hours, numericality: { greater_than: 0, less_than_or_equal_to: 24 * 90, only_integer: true }
  validates :hold_days, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 180, only_integer: true }
  validate :percent_within_ceiling

  scope :open_now, -> { where(status: "open") }

  def open? = status == "open"

  def percent? = commission_model == "cpa_percent"

  # What this program pays for one order, in cents.
  #
  # Integer arithmetic throughout: a rate is basis points and a price is cents,
  # so a commission is never a float that rounds differently on two machines.
  # Rounding is toward the merchant on the half cent, because the alternative is
  # paying out more than was earned and reconciling the difference by hand.
  def commission_for(order_value_cents)
    value = order_value_cents.to_i
    return 0 if value.negative?

    case commission_model
    when "cpa_percent" then value * commission_rate / 10_000
    when "cpa_flat", "cpl" then [ commission_rate, value ].min
    else 0
    end
  end

  def attribution_window = attribution_hours.hours

  private

  def percent_within_ceiling
    return unless percent?
    return if commission_rate.to_i <= MAX_PERCENT_BPS

    errors.add(:commission_rate, :exceeds_max_percent, percent: MAX_PERCENT_BPS / 100)
  end
end
