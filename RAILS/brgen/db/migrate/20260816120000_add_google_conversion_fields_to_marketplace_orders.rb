# frozen_string_literal: true

class AddGoogleConversionFieldsToMarketplaceOrders < ActiveRecord::Migration[8.0]
  def change
    # Table name may be marketplace_orders — adjust if your schema differs.
    return unless table_exists?(:marketplace_orders)

    change_table :marketplace_orders, bulk: true do |t|
      t.string :gclid unless column_exists?(:marketplace_orders, :gclid)
      t.datetime :google_conversion_uploaded_at unless column_exists?(:marketplace_orders, :google_conversion_uploaded_at)
    end
  end
end
