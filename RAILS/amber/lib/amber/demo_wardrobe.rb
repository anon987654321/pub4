# frozen_string_literal: true

module Amber
  # Public demo capsule wardrobe for guests (production marketing / TradeDoubler).
  module DemoWardrobe
    DEMO_EMAIL = "demo@amber.brgen.no"
    DEMO_DISPLAY_NAME = "Amber demo"

    module_function

    def user
      User.strict_loading(false).includes(:profile).find_by(email_address: DEMO_EMAIL)
    end

    def available?
      user.present? && items.exists?
    end

    def items
      return Item.none unless user

      user.items.active_wardrobe
    end

    def outfits
      return Outfit.none unless user

      user.outfits.includes(:items).order(created_at: :desc)
    end

    def preview_items(limit: 6)
      items.recent.limit(limit)
    end

    def preview_outfits(limit: 3)
      outfits.limit(limit)
    end
  end
end
