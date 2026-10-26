# frozen_string_literal: true

# A kitchen that delivers only its own neighbourhood needs a way to say so.
# The column is nil by default and nil means "no limit stated": validation
# skips it entirely, the same way every coordinate reader in this engine
# already treats an unset pin (see Takeaway::Restaurant's header — an unset
# fact is not a false one, and refusing orders over a number nobody typed
# would empty the vertical).
class AddDeliveryRadiusToTakeawayRestaurants < ActiveRecord::Migration[8.2]
  def change
    add_column :takeaway_restaurants, :delivery_radius_km, :integer
  end
end
