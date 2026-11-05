# frozen_string_literal: true

# Picks the best discount for a basket (APP_SPEC §5): the most saving active
# PromoCode — percent, fixed or free delivery, compared by computed saving —
# or the Sahtein card's 10th-stamp free wrap when the user has earned it.
# Order#compute_totals! consumes the returned hash verbatim via
# Order#apply_promo_result!.
class PromoApplier
  # ≥ 9 unredeemed stamps → the wrap is on the house; the 10th stamp IS the
  # reward (APP_SPEC §5, User#free_wrap_ready?).
  LOYALTY_STAMP_THRESHOLD = 9

  # Spec tie-break preference: percent → fixed → free_delivery, then loyalty.
  PREFERRED_ORDER = { "percent" => 0, "fixed" => 1, "free_delivery" => 2 }.freeze

  class << self
    # Returns { promo: PromoCode|nil, discount_ore: Integer,
    #           delivery_fee_ore: Integer, source: :none|:promo|:loyalty }.
    # delivery_fee_ore is the base fee, zeroed when a free_delivery promo
    # wins. Never raises; best pick wins, nothing is applied here.
    def call(subtotal_ore:, delivery_mode: "delivery", user: nil, delivery_fee_ore: nil)
      subtotal = subtotal_ore.to_i
      base_fee = delivery_mode == "pickup" ? 0 : delivery_fee_ore.to_i

      candidates = promo_candidates(subtotal, base_fee, delivery_mode)
      if (loyalty = loyalty_candidate(subtotal, user))
        candidates << loyalty
      end

      best = candidates.max_by { |candidate| candidate[:saving] }
      return none_result(base_fee) if best.nil? || best[:saving] <= 0

      if best[:promo]
        free_delivery = best[:promo].kind == "free_delivery"
        {
          promo: best[:promo],
          # Free delivery zeroes the fee, not the basket (AGENTS contract):
          # its "saving" is the fee it removes, never a basket discount.
          discount_ore: free_delivery ? 0 : best[:saving],
          delivery_fee_ore: free_delivery ? 0 : base_fee,
          source: :promo
        }
      else
        { promo: nil, discount_ore: best[:saving], delivery_fee_ore: base_fee, source: :loyalty }
      end
    end

    private

    def none_result(base_fee)
      { promo: nil, discount_ore: 0, delivery_fee_ore: base_fee, source: :none }
    end

    # Qualified codes in spec preference order; max_by keeps the first on
    # saving ties, so percent beats fixed beats free delivery.
    def promo_candidates(subtotal, base_fee, delivery_mode)
      candidates = PromoCode.active.filter_map do |promo|
        next if subtotal < promo.min_basket_ore.to_i

        saving =
          case promo.kind
          when "percent" then subtotal * promo.value.to_i / 100
          when "fixed" then promo.value.to_i
          when "free_delivery" then delivery_mode == "delivery" ? base_fee : 0
          end

        saving = saving.to_i.clamp(0, subtotal)
        next if saving <= 0

        { promo: promo, saving: saving }
      end

      candidates.sort_by { |candidate| PREFERRED_ORDER.fetch(candidate[:promo].kind, 3) }
    end

    def loyalty_candidate(subtotal, user)
      return nil unless user&.free_wrap_ready?

      price = cheapest_wrap_price_ore
      return nil if price.nil? || price <= 0

      { promo: nil, saving: [ price, subtotal ].min }
    end

    # The cheapest wrap on the menu — matched on the category slug/name so it
    # survives seed tweaks ("Wraps & Ruller", "wraps-ruller", …).
    def cheapest_wrap_price_ore
      MenuItem.available
              .joins(:menu_category)
              .where("LOWER(menu_categories.slug) LIKE :w OR LOWER(menu_categories.name) LIKE :w", w: "%wrap%")
              .minimum(:price_ore)
    end
  end
end
