# frozen_string_literal: true

require "securerandom"

class Order < ApplicationRecord
  class InvalidTransition < StandardError; end

  # placed → confirmed → preparing → ready → picked_up → delivered, plus cancelled.
  FLOW = %w[placed confirmed preparing ready picked_up delivered].freeze
  STATES = (FLOW + %w[cancelled]).freeze
  PAYMENT_STATES = %w[pending authorised captured failed].freeze

  # The staff board advances only through the kitchen's states; the courier
  # owns picked_up/delivered, and cancel is mercy before the pan heats up.
  ADVANCEABLE = %w[placed confirmed preparing].freeze
  CANCELABLE = %w[placed confirmed].freeze

  belongs_to :user, optional: true
  belongs_to :kitchen
  belongs_to :cart, optional: true
  has_many :order_items, dependent: :destroy
  has_one :review, dependent: :destroy

  normalizes :postcode, with: ->(postcode) { postcode.to_s.gsub(/\s+/, "") }
  normalizes :phone, with: ->(phone) { phone.to_s.gsub(/\s+/, "") }

  validates :state, inclusion: { in: STATES }
  validates :payment_state, inclusion: { in: PAYMENT_STATES }
  validates :delivery_mode, inclusion: { in: %w[delivery pickup] }, allow_nil: true
  validates :phone, presence: true
  validates :customer_name, length: { maximum: 80 }
  validates :delivery_note, length: { maximum: 200 }
  validates :tracking_token, presence: true, uniqueness: true

  before_validation :assign_tracking_token
  before_validation :set_placed_at, on: :create

  scope :recent, -> { order(placed_at: :desc, id: :desc) }
  scope :live, -> { where(state: %w[placed confirmed preparing ready picked_up]) }
  scope :for_state, ->(state) { where(state: state) }

  # --- State machine (plain string state + guard methods — APP_SPEC §4) ---

  # Kitchen move: placed → confirmed → preparing → ready. From ready the
  # board shows "—" and the courier takes over.
  def advance!
    next_state = { "placed" => "confirmed", "confirmed" => "preparing", "preparing" => "ready" }[state]
    raise InvalidTransition, "cannot advance an order from #{state.inspect}" unless next_state

    update!(state: next_state)
    self
  end

  def pickup!
    raise InvalidTransition, "cannot pick up an order in #{state.inspect}" unless state == "ready"

    update!(state: "picked_up")
    self
  end

  def deliver!
    raise InvalidTransition, "cannot deliver an order in #{state.inspect}" unless state == "picked_up"

    update!(state: "delivered")
    award_stamp!
    self
  end

  def cancel!
    raise InvalidTransition, "cannot cancel an order in #{state.inspect}" unless CANCELABLE.include?(state)

    update!(state: "cancelled")
    self
  end

  # The address with the customer's note (door code, floor) for a courier.
  def courier_comment
    [address, delivery_note].compact_blank.join(" — ")
  end

  # Who to ask for at the door: the name given, else the number.
  def addressee
    customer_name.presence || phone
  end

  def delivery?
    delivery_mode != "pickup"
  end

  def pickup?
    delivery_mode == "pickup"
  end

  # --- Money (integer øre everywhere) --------------------------------------

  # PromoApplier's result — { promo:, discount_ore:, delivery_fee_ore: } —
  # lands here; nothing else writes the discount columns.
  def apply_promo_result!(result)
    result ||= {}
    self.discount_ore = result[:discount_ore].to_i
    self.delivery_fee_ore = result[:delivery_fee_ore].to_i if result.key?(:delivery_fee_ore)
    self.promo_code = result[:promo]&.code
    self
  end

  # Final math: subtotal (from the cart snapshot) − discount + delivery fee + tip.
  def compute_totals!(zone, promo_result = nil)
    self.delivery_fee_ore = pickup? ? 0 : (zone&.fee_ore).to_i
    self.eta_minutes = pickup? ? nil : zone&.eta_minutes
    apply_promo_result!(promo_result) if promo_result
    self.total_ore = subtotal_ore.to_i - discount_ore.to_i + delivery_fee_ore.to_i + tip_ore.to_i
    save!
    self
  end

  # Tips happen after delivery, on the tracking page; the total bumps live.
  def add_tip!(ore)
    amount = Integer(ore)
    raise ArgumentError, "tip must be a positive amount of øre" unless amount.positive?

    self.tip_ore += amount
    self.total_ore += amount
    save!
    self
  end

  # Denormalised snapshot: order_items are frozen copies of cart_items, prices
  # and option lists included, so a later menu edit never rewrites an order.
  # Builds unsaved lines on a new order (CheckoutController) and creates rows
  # on a persisted one — one snapshot implementation, both paths.
  def snapshot_from_cart!(cart)
    self.cart = cart
    cart.cart_items.includes(:menu_item).find_each do |line|
      attrs = line.order_line_attributes
      new_record? ? order_items.build(attrs) : order_items.create!(attrs)
    end
    self.subtotal_ore = order_items.sum(&:line_total_ore)
    self
  end

  # One stamp per delivered order — the Sahtein card's whole economy.
  def award_stamp!
    return false unless user
    return false if LoyaltyStamp.exists?(order_id: id)

    LoyaltyStamp.create!(user: user, order: self, awarded_at: Time.current)
  end

  private

  def assign_tracking_token
    self.tracking_token ||= SecureRandom.hex(10)
  end

  def set_placed_at
    self.placed_at ||= Time.current
  end
end
