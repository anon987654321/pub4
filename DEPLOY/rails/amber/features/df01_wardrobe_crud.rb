# frozen_string_literal: true
# DF01: wardrobe item CRUD — garment, colour, brand, occasion, season.

module Amber
  module WardrobeCrud
    PERMITTED = %i[name brand category color_primary color_hex material size condition season occasion purchase_price_ore purchased_at].freeze

    module_function

    def create!(user:, params:)
      user.items.create!(params.slice(*PERMITTED))
    end

    def update!(item:, params:)
      item.update!(params.slice(*PERMITTED))
      item
    end

    def destroy!(item:)
      item.destroy!
    end
  end
end