# frozen_string_literal: true

# Where a parcel goes.
#
# Kept as its own record rather than fields on the checkout, because someone who
# buys twice should not type their address twice, and because an address that
# changes must not rewrite the one printed on last month's label.
class Marketplace::Address < ApplicationRecord
  belongs_to :user

  validates :recipient, :line1, :postcode, :city_name, :country_code, presence: true
  validates :country_code, length: { is: 2 }

  scope :default_first, -> { order(default_address: :desc, created_at: :desc) }

  before_save :demote_other_defaults, if: -> { default_address? && default_address_changed? }

  def to_s
    [ recipient, line1, line2, "#{postcode} #{city_name}", country_code ].compact_blank.join(", ")
  end

  private

  # One default, enforced here rather than by a partial index, because SQLite
  # will happily hold two and the wrong parcel goes to the wrong flat.
  def demote_other_defaults
    self.class.where(user_id: user_id).where.not(id: id).update_all(default_address: false, updated_at: Time.current)
  end
end
