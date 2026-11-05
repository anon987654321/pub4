# frozen_string_literal: true

class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :loyalty_stamps, dependent: :destroy
  has_many :orders, dependent: :destroy

  # Roles: customer/staff/courier/admin — the phone is the identity, the role
  # the permission (staff board, courier runs).
  enum :role, { customer: 0, staff: 1, courier: 2, admin: 3 }, default: :customer

  # "900 00 000", "90000000 " and "90000000" are the same customer.
  normalizes :phone, with: ->(phone) { phone.to_s.gsub(/\s+/, "") }

  validates :phone, presence: true, uniqueness: true, format: { with: /\A\d{8,12}\z/ }

  # The name shown in greetings ("Ahlan, Ola!") — falls back to the phone.
  def display_name
    name.presence || phone
  end

  # --- Sahtein-kortet (loyalty) -------------------------------------------
  # Ten stamps buy a free wrap; PromoApplier honours >= 9 unredeemed, because
  # the tenth stamp IS the reward.

  def stamp_count
    loyalty_stamps.count
  end

  def unredeemed_stamp_count
    loyalty_stamps.unredeemed.count
  end

  # The order a free wrap spends them in.
  def unredeemed_stamps_oldest_first
    loyalty_stamps.unredeemed.order(:awarded_at, :id)
  end

  def free_wrap_ready?
    unredeemed_stamp_count >= 9
  end
end
