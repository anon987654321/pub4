# frozen_string_literal: true

# The fourteen EU allergens a dish contains, as a JSON list of keys
# (Takeaway::MenuItem::ALLERGENS). NULL means the kitchen has not said, which
# is not the same as an empty list (says: none of the fourteen); every existing
# dish starts unstated, because nobody but the kitchen knows.
class AddAllergensToTakeawayMenuItems < ActiveRecord::Migration[8.1]
  def change
    add_column :takeaway_menu_items, :allergens, :text
  end
end
