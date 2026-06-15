# frozen_string_literal: true

class AddAn6Features < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :trending_score, :float, default: 0.0, null: false
    add_column :posts, :link_preview, :json, default: {}

    create_table :polls do |t|
      t.references :post, null: false, foreign_key: true
      t.datetime :closes_at, null: false
      t.integer :options_count, default: 0
      t.timestamps
    end

    create_table :poll_options do |t|
      t.references :poll, null: false, foreign_key: true
      t.string :label, null: false
      t.timestamps
    end

    create_table :poll_votes do |t|
      t.references :poll_option, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    create_table :marketplace_offers do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      t.references :buyer, null: false, foreign_key: { to_table: :users }
      t.references :seller, null: false, foreign_key: { to_table: :users }
      t.integer :amount_cents, null: false
      t.integer :status, default: 0, null: false
      t.timestamps
    end

    create_table :check_ins do |t|
      t.references :user, null: false, foreign_key: true
      t.references :place, null: false, foreign_key: true
      t.timestamps
    end
  end
end