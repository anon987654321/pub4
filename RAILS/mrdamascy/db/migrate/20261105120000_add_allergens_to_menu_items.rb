# frozen_string_literal: true

# Distance sales must name the 14 EU allergens before purchase
# (matinformasjonsforskriften), and a dish kept none. allergens is a comma list
# of MenuItem::ALLERGENS keys, "none" for a dish with none of them, and empty
# until the kitchen records it: no allergen data is made up here.
class AddAllergensToMenuItems < ActiveRecord::Migration[8.0]
  def change
    add_column :menu_items, :allergens, :string
  end
end
