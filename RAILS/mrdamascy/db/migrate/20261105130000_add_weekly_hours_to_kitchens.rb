# frozen_string_literal: true

# opening_hours is display text, so checkout took orders at any hour. A
# kitchen's hours are now structured per weekday ({"mon" => ["11:00", "21:00"]},
# a missing day is closed). Left empty here: no hours are made up for the live
# kitchen, and empty means checkout is not limited by the clock.
class AddWeeklyHoursToKitchens < ActiveRecord::Migration[8.0]
  def change
    add_column :kitchens, :weekly_hours, :json
  end
end
