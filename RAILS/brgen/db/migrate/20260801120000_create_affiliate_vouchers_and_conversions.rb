# frozen_string_literal: true

# TradeDoubler phases 3–4: voucher inventory + conversion postbacks.
#
# Products already live in affiliate_products. Vouchers are time-bounded offers
# (codes, free shipping, exclusives). Conversions close the money loop when
# TradeDoubler POSTs message-type transitions to our webhook.
class CreateAffiliateVouchersAndConversions < ActiveRecord::Migration[8.1]
  def change
    create_table :affiliate_vouchers do |t|
      t.string :source, null: false, limit: 32, default: "tradedoubler"
      t.string :external_id, null: false, limit: 64
      t.string :program_id, limit: 64
      t.string :program_name, limit: 200
      t.string :code, limit: 256
      t.string :title, null: false, limit: 120
      t.string :short_description, limit: 200
      t.text :description
      t.integer :voucher_type_id, null: false, default: 1
      t.text :track_url, null: false
      t.text :landing_url
      t.decimal :discount_amount, precision: 10, scale: 2
      t.boolean :percentage, null: false, default: false
      t.boolean :site_specific, null: false, default: false
      t.boolean :exclusive, null: false, default: false
      t.string :currency, limit: 8
      t.string :market, limit: 8
      t.datetime :starts_at
      t.datetime :ends_at
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :affiliate_vouchers, %i[source external_id], unique: true
    add_index :affiliate_vouchers, %i[market ends_at]
    add_index :affiliate_vouchers, :site_specific

    create_table :affiliate_conversions do |t|
      t.string :source, null: false, limit: 32, default: "tradedoubler"
      t.string :transaction_id, limit: 128
      t.string :legacy_transaction_id, limit: 128
      t.string :order_number, limit: 128
      t.integer :message_type_id, null: false
      t.integer :event_type_id
      t.integer :program_id
      t.integer :site_id
      t.string :site_name, limit: 200
      t.decimal :order_value, precision: 12, scale: 2
      t.decimal :publisher_commission, precision: 12, scale: 2
      t.string :currency, limit: 8
      t.string :product_id, limit: 128
      t.string :product_name, limit: 300
      t.string :epi, limit: 500
      t.string :epi2, limit: 500
      t.string :visitor_id, limit: 128
      t.string :sequence_number, limit: 64
      t.datetime :time_of_event
      t.datetime :time_of_visit
      t.json :raw_payload
      t.timestamps
    end
    add_index :affiliate_conversions, %i[source transaction_id message_type_id],
              name: "index_affiliate_conversions_on_source_txn_message",
              unique: true
    add_index :affiliate_conversions, :order_number
    add_index :affiliate_conversions, :message_type_id
    add_index :affiliate_conversions, :epi
    add_index :affiliate_conversions, :created_at
  end
end
