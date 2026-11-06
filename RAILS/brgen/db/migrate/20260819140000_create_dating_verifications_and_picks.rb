# frozen_string_literal: true

# Two things a dating app is expected to have and this one did not: proof that
# the person in the photos is the person holding the phone, and a short daily
# list that is not the endless deck.
class CreateDatingVerificationsAndPicks < ActiveRecord::Migration[8.1]
  def change
    create_table :dating_verifications do |t|
      t.references :profile, null: false, foreign_key: { to_table: :dating_profiles }
      t.references :reviewed_by, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      # The gesture the app asked for, drawn when the request is made. Stored,
      # because a reviewer comparing a selfie to a pose has to know which pose
      # was asked for — and because asking the same one every time makes a
      # stolen photo enough.
      t.string :pose, null: false
      t.text :review_note
      t.datetime :reviewed_at
      t.timestamps
    end

    add_index :dating_verifications, %i[profile_id status]

    # Denormalised onto the profile because every deck card reads it and a join
    # per card is the shape that made the feed slow before.
    add_column :dating_profiles, :verified_at, :datetime

    # A pick is a row, not a computed slice: the point of a daily list is that
    # it is the same list all day, and that tomorrow's is different.
    create_table :dating_daily_picks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: { to_table: :dating_profiles }
      t.date :picked_on, null: false
      t.datetime :created_at, null: false
    end

    add_index :dating_daily_picks, %i[user_id picked_on]
    add_index :dating_daily_picks, %i[user_id profile_id picked_on], unique: true
  end
end
