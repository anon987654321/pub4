# frozen_string_literal: true

# Three gaps that make a takeaway app answerable.
#
# Nothing modelled whether a kitchen was open, so a restaurant took orders at
# 04:00 and the customer found out when nobody cooked them. Nothing carried a
# tip, which on a delivery app is most of what a courier earns. And nothing let
# an order be placed for later, which is how most food ordering above a certain
# size actually works.
class AddTakeawayHoursAndTips < ActiveRecord::Migration[8.1]
  def change
    # One row per weekday rather than a JSON blob: opening hours are queried
    # ("is it open now"), and a blob makes that a Ruby loop over every
    # restaurant on the page.
    create_table :takeaway_opening_hours do |t|
      t.references :restaurant, null: false, foreign_key: { to_table: :takeaway_restaurants }
      t.integer :weekday, null: false          # 0 = Sunday, matching Time#wday
      t.integer :opens_minute, null: false     # minutes past midnight
      t.integer :closes_minute, null: false
      t.timestamps
    end
    add_index :takeaway_opening_hours, %i[restaurant_id weekday]

    change_table :takeaway_orders, bulk: true do |t|
      # Stored in minor units like every other amount here, so a tip cannot
      # arrive as a float and lose a øre in the sum.
      t.integer  :tip_cents, null: false, default: 0
      # When the customer wants it, as opposed to when they ordered.
      t.datetime :scheduled_for
    end
    add_index :takeaway_orders, :scheduled_for
  end
end
