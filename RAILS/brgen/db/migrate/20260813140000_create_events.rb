# frozen_string_literal: true

# The largest missing noun for a city social network. Place, Neighborhood,
# PlaceCheckIn and the maps engine were all already here; what a city could not
# say was "this is happening, at this time, and here is who is coming".
class CreateEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :events do |t|
      t.references :city, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :place, foreign_key: true
      t.references :neighborhood, foreign_key: true
      t.string  :title, null: false
      t.string  :slug
      t.text    :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string  :venue_name
      t.string  :address
      t.decimal :latitude,  precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.integer :capacity
      t.integer :price_cents
      t.string  :currency
      t.string  :external_url
      t.string  :status, null: false, default: "published"
      t.integer :going_count,     null: false, default: 0
      t.integer :interested_count, null: false, default: 0
      t.integer :comments_count,  null: false, default: 0
      t.datetime :cancelled_at
      t.timestamps
    end

    # Sluggable is unique per city, matching Post and Community.
    add_index :events, %i[city_id slug], unique: true
    # The only ordering any events surface wants: what is on next, in this city.
    add_index :events, %i[city_id status starts_at]
    add_index :events, :starts_at

    create_table :event_rsvps do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user,  null: false, foreign_key: true
      t.string :status, null: false, default: "going"
      t.timestamps
    end

    # One answer per person per event. The controller toggles, so without this a
    # double submit leaves two rows and both counter caches count them.
    add_index :event_rsvps, %i[event_id user_id], unique: true
    add_index :event_rsvps, %i[event_id status]
  end
end
