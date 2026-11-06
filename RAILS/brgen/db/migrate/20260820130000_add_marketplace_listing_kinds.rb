# frozen_string_literal: true

# The non-goods half of a classifieds site: jobs, housing, gigs.
#
# They are listings — same city scoping, same search, same expiry, same
# messaging — and they are not goods: a job has no condition and often no price,
# a room has rent and a date it is free from, a gig has a fee and an evening. So
# the shared half stays on marketplace_listings and each kind gets a table of
# its own, rather than a widening listings table where most columns are null for
# most rows.
class AddMarketplaceListingKinds < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_listings, :kind, :string, null: false, default: "goods"
    add_index :marketplace_listings, %i[kind city_id]

    create_table :marketplace_job_details do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.string :employer
      t.string :employment_type
      # A range, because one number is either a floor somebody reads as the
      # offer or a ceiling nobody is paid. Both nullable: plenty of adverts say
      # nothing about pay, and inventing a number is worse than silence.
      t.integer :salary_min_cents
      t.integer :salary_max_cents
      t.boolean :remote, null: false, default: false
      t.timestamps
    end

    create_table :marketplace_housing_details do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.integer :rent_cents
      t.integer :deposit_cents
      t.decimal :rooms, precision: 4, scale: 1
      t.integer :size_sqm
      t.date :available_from
      t.string :housing_type
      t.timestamps
    end

    create_table :marketplace_gig_details do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.integer :pay_cents
      t.datetime :starts_at
      t.decimal :hours, precision: 5, scale: 1
      t.timestamps
    end

    add_index :marketplace_job_details, :listing_id, unique: true, name: "idx_job_details_listing"
    add_index :marketplace_housing_details, :listing_id, unique: true, name: "idx_housing_details_listing"
    add_index :marketplace_gig_details, :listing_id, unique: true, name: "idx_gig_details_listing"
  end
end
