# frozen_string_literal: true

# The other side of the affiliate relationship.
#
# brgen is already a *publisher* on someone else's network: Affiliate reads
# Tradedoubler and Amazon feeds and shows their deals. These tables make brgen
# the *network* — a city's businesses run partner programs, and the people who
# already post in that city promote them and earn on what they sell.
#
# The economics are the ones that make partner marketing work at all: the
# merchant sets a commission rate, and partners compete inside it at their own
# risk. The merchant's cost per sale cannot exceed the rate they set, so sales
# scale without the cost of sale rising with them.
class CreatePartnerMarketing < ActiveRecord::Migration[8.1]
  def change
    create_table :partner_programs do |t|
      t.references :city, foreign_key: true, index: true
      t.references :store, null: false, foreign_key: { to_table: :marketplace_stores }, index: true
      t.string :name, null: false, limit: 120
      t.string :status, null: false, default: "draft"
      t.string :commission_model, null: false, default: "cpa_percent"
      # Percent in basis points, flat amounts in cents: both integers, so no
      # money or rate is ever held as a float.
      t.integer :commission_rate, null: false, default: 0
      t.integer :attribution_hours, null: false, default: 720
      # How long a conversion stays pending before it can be approved — the
      # merchant's return window. Paying before it closes means clawing back.
      t.integer :hold_days, null: false, default: 30
      t.boolean :auto_approve_partners, null: false, default: false
      t.text :terms
      t.timestamps
    end
    add_index :partner_programs, %i[status city_id]

    create_table :partner_memberships do |t|
      t.references :program, null: false, foreign_key: { to_table: :partner_programs }, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :status, null: false, default: "pending"
      # The whole tracking scheme rests on this token, so it is unique globally
      # rather than per program: a token that can mean two things attributes to
      # the wrong partner exactly when two programs share a visitor.
      t.string :token, null: false, limit: 32
      t.datetime :approved_at
      t.timestamps
    end
    add_index :partner_memberships, :token, unique: true
    add_index :partner_memberships, %i[program_id user_id], unique: true

    create_table :partner_clicks do |t|
      t.references :membership, null: false, foreign_key: { to_table: :partner_memberships }, index: true
      t.references :listing, foreign_key: { to_table: :marketplace_listings }, index: true
      t.references :user, foreign_key: true, index: true
      # Hashed, never raw: this is a visitor fingerprint for dedupe and fraud
      # checks, and it has no business being reversible to an address.
      t.string :visitor_digest, limit: 64
      t.datetime :occurred_at, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    # The attribution lookup: newest live click for a visitor.
    add_index :partner_clicks, %i[visitor_digest expires_at]

    create_table :partner_conversions do |t|
      t.references :membership, null: false, foreign_key: { to_table: :partner_memberships }, index: true
      t.references :click, foreign_key: { to_table: :partner_clicks }, index: true
      t.references :order, null: false, foreign_key: { to_table: :marketplace_orders }, index: true
      t.string :status, null: false, default: "pending"
      t.integer :order_value_cents, null: false, default: 0
      t.integer :commission_cents, null: false, default: 0
      t.string :currency, null: false, default: "NOK", limit: 3
      t.datetime :payable_after, null: false
      t.datetime :approved_at
      t.datetime :paid_at
      t.string :rejected_reason, limit: 200
      t.timestamps
    end
    # One conversion per order. Attribution runs from a payment webhook, and
    # webhooks are retried: without this, a retry pays the partner twice.
    add_index :partner_conversions, :order_id, unique: true
    add_index :partner_conversions, %i[status payable_after]
  end
end
