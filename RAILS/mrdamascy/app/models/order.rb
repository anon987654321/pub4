# frozen_string_literal: true

require "securerandom"

class Order < ApplicationRecord
  class InvalidTransition < StandardError; end

  # placed → confirmed → preparing → ready → picked_up → delivered, plus cancelled.
  FLOW = %w[placed confirmed preparing ready picked_up delivered].freeze
  STATES = (FLOW + %w[cancelled]).freeze
  PAYMENT_STATES = %w[pending authorised captured failed].freeze
  # Money reserved or taken: a cancelled order in one of these owes it back.
  PAID_STATES = %w[authorised captured].freeze
  # Neither payment client can refund, so a cancelled paid order is refunded
  # by hand in the provider's portal: manual_due until staff mark it refunded.
  REFUND_STATES = %w[manual_due refunded].freeze

  # The staff board advances only through the kitchen's states; the courier
  # owns picked_up/delivered, and cancel is mercy before the pan heats up.
  ADVANCEABLE = %w[placed confirmed preparing].freeze
  CANCELABLE = %w[placed confirmed].freeze
  # The moves whose moment is kept (placed_at is set on create), so ETAs
  # and the board can be measured.
  TIMED_STATES = %w[confirmed ready picked_up delivered].freeze
  # The staff board's columns; from ready the courier takes over.
  BOARD_STATES = %w[placed confirmed preparing ready].freeze

  belongs_to :user, optional: true
  belongs_to :kitchen
  belongs_to :cart, optional: true
  has_many :order_items, dependent: :destroy
  has_one :review, dependent: :destroy
  # The stamps this order's free wrap spent (PromoApplier's loyalty pick).
  has_many :redeemed_stamps, class_name: "LoyaltyStamp", foreign_key: :redeemed_order_id,
                             inverse_of: :redeemed_order, dependent: :nullify

  normalizes :postcode, with: ->(postcode) { postcode.to_s.gsub(/\s+/, "") }
  normalizes :phone, with: ->(phone) { phone.to_s.gsub(/\s+/, "") }

  validates :state, inclusion: { in: STATES }
  validates :payment_state, inclusion: { in: PAYMENT_STATES }
  validates :refund_state, inclusion: { in: REFUND_STATES }, allow_nil: true
  validates :delivery_mode, inclusion: { in: %w[delivery pickup] }, allow_nil: true
  validates :phone, presence: true
  validates :customer_name, length: { maximum: 80 }
  validates :delivery_note, length: { maximum: 200 }
  validates :tracking_token, presence: true, uniqueness: true

  before_validation :assign_tracking_token
  before_validation :set_placed_at, on: :create
  # Covers both a paid order cancelled from the board and a payment that lands
  # after the order was cancelled (a late webhook or tracking sync). A 0 kr
  # order (PaymentGateway's free settle) took nothing, so it owes nothing.
  before_save :owe_manual_refund,
              if: -> { state == "cancelled" && refund_state.nil? && PAID_STATES.include?(payment_state) && paid_for? }

  # The staff board is pushed, not polled: a new order or a move redraws
  # its grid for every open board.
  # (One after_commit: create and update hooks naming the same method keep
  # only the last.)
  after_commit :refresh_board, on: %i[create update], if: -> { previously_new_record? || saved_change_to_state? }
  # A free wrap that is never paid for or never made gives its stamps back.
  after_update :release_redeemed_stamps,
               if: -> { saved_change_to_state?(to: "cancelled") || saved_change_to_payment_state?(to: "failed") }

  scope :recent, -> { order(placed_at: :desc, id: :desc) }
  scope :live, -> { where(state: %w[placed confirmed preparing ready picked_up]) }
  scope :for_state, ->(state) { where(state: state) }
  scope :refunds_due, -> { where(refund_state: "manual_due").order(:updated_at, :id) }

  # The board's orders by column, oldest first.
  def self.board_columns
    where(state: BOARD_STATES).includes(:order_items).order(:placed_at, :id).group_by(&:state)
  end

  # --- State machine (plain string state + guard methods — APP_SPEC §4) ---

  # Kitchen move: placed → confirmed → preparing → ready. From ready the
  # board shows "—" and the courier takes over.
  def advance!
    next_state = { "placed" => "confirmed", "confirmed" => "preparing", "preparing" => "ready" }[state]
    raise InvalidTransition, "cannot advance an order from #{state.inspect}" unless next_state

    move_to!(next_state)
    self
  end

  def pickup!
    raise InvalidTransition, "cannot pick up an order in #{state.inspect}" unless state == "ready"

    move_to!("picked_up")
    self
  end

  def deliver!
    raise InvalidTransition, "cannot deliver an order in #{state.inspect}" unless state == "picked_up"

    move_to!("delivered")
    award_stamp!
    self
  end

  def cancel!
    raise InvalidTransition, "cannot cancel an order in #{state.inspect}" unless CANCELABLE.include?(state)

    update!(state: "cancelled")
    self
  end

  def refund_due?
    refund_state == "manual_due"
  end

  # Staff made the refund by hand in Vipps' or Stripe's portal.
  def mark_refunded!
    raise InvalidTransition, "order #{id} owes no refund" unless refund_due?

    update!(refund_state: "refunded")
    self
  end

  # The provider whose portal takes the manual refund.
  def payment_lane_name
    payment_method == "stripe" ? "Stripe" : "Vipps"
  end

  # The address with the customer's note (door code, floor) for a courier.
  def courier_comment
    [ address, delivery_note ].compact_blank.join(" — ")
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
    transaction do
      save!
      redeem_free_wrap_stamps! if promo_result&.dig(:source) == :loyalty
    end
    self
  end

  # Tips happen after delivery, on the tracking page, once per order. The
  # payment was captured before the food left, and neither lane can charge
  # again, so the tip is kept beside the total and never added to it:
  # total_ore stays what the customer paid, and the order page names the tip
  # as not paid in the app.
  def add_tip!(ore)
    amount = Integer(ore)
    raise ArgumentError, "tip must be a positive amount of øre" unless amount.positive?
    raise InvalidTransition, "tips are taken on delivered orders only" unless state == "delivered"
    raise InvalidTransition, "this order already has a tip" if tipped?

    update!(tip_ore: amount)
    self
  end

  # Money was asked for: a 0 kr order never reached a payment provider.
  def paid_for?
    total_ore.to_i.positive?
  end

  def tipped?
    tip_ore.to_i.positive?
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

  # "Yalla igjen": every line of this order back into a cart, with the
  # options it had (matched by name, as the snapshot keeps them) and its
  # note, at today's prices. A dish off the menu or whose options changed
  # is left out; answers how many lines could not come back.
  def reorder_into!(cart)
    order_items.count do |line|
      item = MenuItem.find_by(id: line.menu_item_id)
      next true unless item

      options = ItemOption.where(menu_item_id: item.id, name: line.options_text.to_s.split(", ")).pluck(:id)
      cart.add_item!(item, line.quantity, option_ids: options, note: line.note)
      false
    rescue Cart::InvalidLine
      true
    end
  end

  # One stamp per delivered order — the Sahtein card's whole economy. The
  # order a free wrap paid for earns the tenth stamp, which is the reward
  # itself, so it is spent with the nine before it and the card starts over.
  def award_stamp!
    return false unless user
    return false if LoyaltyStamp.exists?(order_id: id)

    free_wrap = redeemed_stamps.exists?
    LoyaltyStamp.create!(user: user, order: self, awarded_at: Time.current,
                         redeemed: free_wrap, redeemed_order: (self if free_wrap))
  end

  private

  # The free wrap spends the nine oldest unredeemed stamps, in the order's own
  # save. Fewer than nine left (another checkout spent them first) and the
  # order is refused instead of giving the wrap away twice.
  def redeem_free_wrap_stamps!
    needed = PromoApplier::LOYALTY_STAMP_THRESHOLD
    stamps = user.unredeemed_stamps_oldest_first
    ids = stamps.limit(needed).pluck(:id)
    spent = LoyaltyStamp.unredeemed.where(id: ids)
                        .update_all(redeemed: true, redeemed_order_id: id, updated_at: Time.current)
    raise ActiveRecord::RecordInvalid, self unless spent == needed
  end

  def owe_manual_refund
    self.refund_state = "manual_due"
  end

  def release_redeemed_stamps
    redeemed_stamps.update_all(redeemed: false, redeemed_order_id: nil, updated_at: Time.current)
  end

  def refresh_board
    Turbo::StreamsChannel.broadcast_replace_to(
      "staff_board", target: "board_grid", partial: "staff/board/grid",
                      locals: { orders_by_state: Order.board_columns }
    )
  end

  def move_to!(next_state)
    times = TIMED_STATES.include?(next_state) ? { "#{next_state}_at" => Time.current } : {}
    update!(state: next_state, **times)
  end

  def assign_tracking_token
    self.tracking_token ||= SecureRandom.hex(10)
  end

  def set_placed_at
    self.placed_at ||= Time.current
  end
end
