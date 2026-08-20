# frozen_string_literal: true

class Takeaway::Order < ApplicationRecord
  include Shared::Notifiable
  tracks_activity created: "TakeawayOrderPlaced", source_vertical: "takeaway", actor: :user

  belongs_to :user
  belongs_to :restaurant, class_name: "Takeaway::Restaurant"
  # delivery_driver_id and its composite [delivery_driver_id, status] index have
  # been on this table since it was created, and Takeaway::DeliveryDriver has
  # had the matching has_many :orders — but there was no belongs_to here and
  # nothing ever wrote the column, so every order went out for delivery with no
  # courier attached. See #dispatch_driver_id below.
  belongs_to :delivery_driver, class_name: "Takeaway::DeliveryDriver", optional: true
  has_many :order_items, class_name: "Takeaway::OrderItem", dependent: :destroy
  has_many :reviews, class_name: "Takeaway::Review", dependent: :destroy

  STATUSES = %w[pending confirmed preparing out_for_delivery delivered cancelled].freeze
  TERMINAL_STATUSES = %w[delivered cancelled].freeze
  TRANSITIONS = {
    "pending" => %w[confirmed cancelled],
    "confirmed" => %w[preparing cancelled],
    "preparing" => %w[out_for_delivery cancelled],
    "out_for_delivery" => %w[delivered],
    "delivered" => [],
    "cancelled" => []
  }.freeze
  CENTS_PER_KRONE = 100.0

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_address, presence: true

  before_validation { self.status ||= "pending" }
  validate :status_transition_allowed, on: :update
  validate :meets_minimum_order, on: :create
  validate :has_line_items, on: :create

  # One ticket, several people. The host is `user` — the person who opened it
  # and the only one who can send it to the kitchen — and every line knows who
  # added it.
  def open_group!
    update!(group_open: true, group_token: group_token.presence || SecureRandom.urlsafe_base64(12))
  end

  def group? = group_token.present?
  def host?(candidate) = candidate.present? && candidate.id == user_id

  # Anyone with the link may add to an open ticket that has not left yet. Once
  # it is confirmed the kitchen is cooking it, and a late line is a different
  # order rather than a surprise on this one.
  def joinable? = group? && group_open? && status == "pending"

  # What each person owes, so the ticket can be split without anybody doing
  # arithmetic in a chat. Delivery and tip stay the host's — splitting a fee
  # four ways to the øre is a worse argument than paying it.
  def shares
    order_items.group_by(&:user_id).transform_values { |items| items.sum(&:subtotal_cents) }
  end

  scope :active, -> { where.not(status: TERMINAL_STATUSES) }
  scope :recent, -> { order(created_at: :desc) }

  def calculate_totals!
    # Use in-memory association target so create-with-build works under strict_loading.
    items = order_items.target
    sub = items.sum { |oi| oi.unit_price_cents.to_i * oi.quantity.to_i }
    # The comment above covers order_items, but the delivery fee was still a lazy
    # belongs_to read — so this raised on any order loaded from the database
    # rather than built in memory.
    fee = strict_safe_attribute(:restaurant, :delivery_fee_cents).to_i
    # The tip is part of what is charged, so it belongs in the total rather than
    # being added at some later point nobody can find.
    update!(subtotal_cents: sub, delivery_fee_cents: fee, total_cents: sub + fee + tip_cents.to_i)
  end

  def advance_status!
    transition_to!(next_status)
  end

  def transition_to!(next_status)
    unless may_transition_to?(next_status)
      errors.add(:status, :bad_transition, from: status, to: next_status)
      return false
    end

    attrs = { status: next_status }
    # Dispatch on the same write as the status change, so an order is never
    # observable as out_for_delivery with no courier attached. A nil id is left
    # out rather than written: no free driver in range means the order still
    # leaves the kitchen, it just has nobody named on it yet.
    if next_status.to_s == "out_for_delivery" && delivery_driver_id.blank?
      assigned = dispatch_driver_id
      attrs[:delivery_driver_id] = assigned if assigned
    end
    update!(attrs)
    # `user`, `restaurant.name` and `restaurant.user` are all lazy reads, and an
    # order loaded by id (controller, driver request, job) has none of them
    # preloaded. Under strict loading — on in every environment, raising outside
    # development — this raised immediately after update! had committed the new
    # status: the order advanced, the customer was never told, and the caller saw
    # a 500. See Shared::StrictSafeAssociations.
    label = I18n.t("takeaway.statuses.#{status}", default: status.to_s)
    restaurant_record = strict_safe(:restaurant)
    courier = courier_display_name
    body = I18n.t("takeaway.order_status_body", restaurant: restaurant_record&.name, status: label)
    body += " #{I18n.t("takeaway.order_status_courier", courier: courier)}" if courier
    deliver_notification(strict_safe(:user),
      title: I18n.t("takeaway.order_status_title", status: label),
      body: body,
      source: self,
      # Waiting on food is the case a push exists for.
      kind: "order")
    record_activity!("TakeawayOrderUpdated",
      actor: restaurant_record&.user,
      source_vertical: "takeaway",
      locality: restaurant_record&.[](:city),
      visibility: "private")
    true
  end

  def advanceable?
    next_status.present?
  end

  def may_transition_to?(next_status)
    TRANSITIONS.fetch(status, []).include?(next_status.to_s)
  end

  # Minutes from order placement to the end of each stage. Anchored to
  # created_at (not "now") so the estimate visibly shrinks as the order
  # actually advances, instead of a fixed "25-35 min" string that never
  # reflects what's really happening to this order.
  ETA_MINUTES_BY_STATUS = {
    "pending" => 35,
    "confirmed" => 30,
    "preparing" => 20,
    "out_for_delivery" => 10,
    "delivered" => 0
  }.freeze

  def scheduled? = scheduled_for.present?

  # A scheduled order is not late because it was placed hours ago: its estimate
  # is anchored to when the customer asked for it, not to when they ordered.
  def estimated_ready_at
    return nil if status == "cancelled"
    return scheduled_for if scheduled? && scheduled_for > Time.current

    anchor = scheduled? ? scheduled_for : created_at
    anchor + ETA_MINUTES_BY_STATUS.fetch(status, 30).minutes
  end

  # Fraction of the delivery journey complete, for a real (non-decorative)
  # progress fill under the status timeline. nil once terminal — there's
  # nothing left to fill toward.
  def progress_fraction
    return nil if TERMINAL_STATUSES.include?(status)
    stages = STATUSES - TERMINAL_STATUSES
    (stages.index(status).to_i + 1) / stages.size.to_f
  end

  # How far from the kitchen dispatch will look for a courier. Bergen end to end
  # is about 10 km, so this is "anywhere in the city" rather than a tuned value.
  DISPATCH_RADIUS_KM = 10

  # The courier's name for customer-facing copy, or nil when nobody is assigned.
  # strict_safe because an order loaded by id has no association preloaded.
  def courier_display_name
    strict_safe(:delivery_driver)&.display_name
  end

  # Kitchen to customer, as the courier actually has to travel it. nil unless
  # both ends have coordinates — the order page falls back to the status ETA.
  def courier_distance_km
    driver = strict_safe(:delivery_driver)
    return nil unless driver&.location?

    restaurant_record = strict_safe(:restaurant)
    return nil unless restaurant_record&.latitude && restaurant_record&.longitude

    Takeaway::DeliveryDriver.haversine(
      driver.current_lat, driver.current_lng,
      restaurant_record.latitude, restaurant_record.longitude
    )
  end

  def next_status = TRANSITIONS.fetch(status, []).first
  # A new pending order with the same address and whatever is still on the
  # menu. Tip and scheduled_for stay off — those are per-ticket decisions.
  def build_reorder
    kitchen = strict_safe(:restaurant)
    copy = kitchen.orders.build(
      user: strict_safe(:user),
      delivery_address: delivery_address,
      special_instructions: special_instructions
    )
    order_items.each do |oi|
      item = oi.association(:menu_item).loaded? ? oi.menu_item : oi.strict_safe(:menu_item)
      # available_for_order? reads item.restaurant. Point the inverse at the
      # kitchen we already have so the create validation does not lazy-load.
      next unless item&.available? && kitchen.active?

      item.association(:restaurant).target = kitchen unless item.association(:restaurant).loaded?
      copy.order_items.build(
        menu_item: item,
        quantity: oi.quantity,
        unit_price_cents: item.price_cents
      )
    end
    copy
  end

  def cancel! = transition_to!("cancelled")
  def confirm! = transition_to!("confirmed")
  def prepare! = transition_to!("preparing")
  def dispatch! = transition_to!("out_for_delivery")
  def deliver! = transition_to!("delivered")

  def subtotal_display
    amount_display(subtotal_cents)
  end

  def delivery_fee_display
    amount_display(delivery_fee_cents)
  end

  def total_display
    amount_display(total_cents)
  end

  def tip_display
    amount_display(tip_cents)
  end

  private

  # Nearest free courier to the kitchen, or nil. Deliberately not a validation
  # or a callback: an order with nobody to carry it is a real operational state
  # (nobody on shift at 3am), and refusing the transition would strand it in
  # `preparing` forever rather than surfacing the problem.
  def dispatch_driver_id
    restaurant_record = strict_safe(:restaurant)
    return nil unless restaurant_record&.latitude && restaurant_record&.longitude

    Takeaway::DeliveryDriver.nearest_free(
      restaurant_record.latitude,
      restaurant_record.longitude,
      DISPATCH_RADIUS_KM
    )&.id
  end

  def amount_display(cents)
    Shared::MoneyDisplay.format(cents)
  end

  # The restaurant advertises a minimum-order threshold (shown as a chip on its
  # page); before this, checkout ignored it and let a 30-kr order through against
  # a 150-kr minimum. Read items in memory (like calculate_totals!) so this holds
  # during create-with-build under strict loading; `restaurant` is the in-memory
  # object the controller assigned, not a lazy DB read.
  def has_line_items
    return if order_items.target.any?

    errors.add(:base, :empty_order)
  end

  def meets_minimum_order
    min = restaurant&.min_order_cents.to_i
    return if min <= 0

    sub = order_items.target.sum { |oi| oi.unit_price_cents.to_i * oi.quantity.to_i }
    return if sub >= min

    errors.add(:base, :below_minimum, restaurant: restaurant.name, minimum: restaurant.min_order_display, subtotal: amount_display(sub))
  end

  def status_transition_allowed
    return unless will_save_change_to_status?
    previous_status = status_in_database
    return if previous_status.blank?
    return if TRANSITIONS.fetch(previous_status, []).include?(status)

    errors.add(:status, :bad_transition, from: previous_status, to: status)
  end
end
