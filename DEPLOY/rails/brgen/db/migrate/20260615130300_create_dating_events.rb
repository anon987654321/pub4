# frozen_string_literal: true

class CreateDatingEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :dating_events do |t|
      t.string :title, null: false
      t.text :description
      t.string :venue
      t.string :city
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.references :user, foreign_key: true
      t.timestamps
    end

    create_table :dating_event_rsvps do |t|
      t.references :dating_event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "going"
      t.timestamps
    end

    add_index :dating_event_rsvps, %i[dating_event_id user_id], unique: true
  end
end