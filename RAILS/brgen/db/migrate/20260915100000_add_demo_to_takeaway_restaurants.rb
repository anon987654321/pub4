# frozen_string_literal: true

# The Bergen demo seed publishes restaurants under the names of real Bergen
# businesses, with menus, prices and delivery fees nobody at those businesses
# wrote. Nothing on the row said it was seeded, so brgen.no sitemapped them and
# described each as a LocalBusiness. `demo` is that marker: the page stays, and
# a demo restaurant is left out of the sitemap and structured data and marked
# noindex.
#
# The backfill names each seeded restaurant together with the seeded account
# that owns it, as Brgen::BergenDemoData::RESTAURANTS creates them, so a real
# restaurant that happens to share a name is not marked. Spelled out rather than
# read from that constant, because a migration outlives the code it ran beside.
# Setting the flag back to false, or renaming the restaurant, is the whole of
# undoing it.
class AddDemoToTakeawayRestaurants < ActiveRecord::Migration[8.1]
  SEEDED = {
    "Colonialen" => "ola_nordnes",
    "Fish Me" => "anders_fisketorget",
    "Potetkjelleren" => "henrik_vestland",
    "Dyvekes" => "sofie_regnby"
  }.freeze

  def up
    add_column :takeaway_restaurants, :demo, :boolean, default: false, null: false
    mark_seeded
  end

  def mark_seeded
    SEEDED.each do |name, owner|
      execute(ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, name, owner ]))
        UPDATE takeaway_restaurants
           SET demo = TRUE
         WHERE name = ?
           AND user_id IN (SELECT id FROM users WHERE username = ?)
      SQL
    end
  end

  def down
    remove_column :takeaway_restaurants, :demo
  end
end
