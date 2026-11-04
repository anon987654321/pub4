# frozen_string_literal: true

class Cart < ApplicationRecord
  # A line the menu does not offer: a foreign option id or too many sauces.
  class InvalidLine < StandardError; end

  # The item sheet's chip cap, enforced here too so the form is not the guard.
  MAX_SAUCES = 2

  belongs_to :user, optional: true
  has_many :cart_items, dependent: :destroy

  normalizes :session_key, with: ->(key) { key.to_s.strip }

  validates :session_key, presence: true, unless: :user

  # One open cart per identity (APP_SPEC §4): a signed-in user carts by
  # user_id, an anonymous visitor by the session_key cookie. Find-or-create.
  def self.for(user, session_key)
    if user
      where(user_id: user.id).first_or_create!(session_key: session_key)
    else
      raise ArgumentError, "session_key is required for anonymous carts" if session_key.blank?

      where(session_key: session_key).first_or_create!
    end
  end

  # Snapshot pricing: unit_price_ore freezes the menu price plus the selected
  # options' prices at add-time, so a later menu edit never rewrites a line
  # already in someone's basket. Identical lines (item + options + note)
  # merge by bumping quantity.
  def add_item!(menu_item, quantity = 1, option_ids: [], note: nil)
    quantity = Integer(quantity)
    quantity = 1 if quantity < 1
    ids = chosen_option_ids(option_ids)
    options = offered_options(menu_item, ids)
    signature = ids.join(",")

    line = cart_items.find_by(menu_item_id: menu_item.id, option_ids: signature, note: note.presence)
    if line
      line.quantity += quantity
    else
      line = cart_items.new(menu_item: menu_item, option_ids: signature, note: note.presence, quantity: quantity)
    end
    line.unit_price_ore = menu_item.price_ore.to_i + options.sum { |o| o.price_ore.to_i }
    line.save!
    line
  end

  def subtotal_ore
    cart_items.sum("unit_price_ore * quantity")
  end

  def total_quantity
    cart_items.sum(:quantity)
  end

  def empty!
    cart_items.destroy_all
    self
  end

  private

  # Form noise guard: a no-option form can deliver [""] (or "") through the
  # params round-trip. Blank ids carry no option, so drop them before the
  # Integer cast instead of 500ing on a legitimate request.
  def chosen_option_ids(option_ids)
    Array(option_ids).compact_blank.to_set { |id| Integer(id) }.sort
  end

  # The form is not the guard: a crafted request can name another dish's
  # option or a third sauce, and every id it names would be priced.
  def offered_options(menu_item, ids)
    options = ItemOption.where(menu_item_id: menu_item.id, id: ids).to_a
    raise InvalidLine, "option not offered with #{menu_item.name}" unless options.size == ids.size
    raise InvalidLine, "more than #{MAX_SAUCES} sauces" if options.count { |o| o.kind == "sauce" } > MAX_SAUCES

    options
  end
end
