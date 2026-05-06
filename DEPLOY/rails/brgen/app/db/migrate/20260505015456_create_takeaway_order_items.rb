class CreateTakeawayOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :takeaway_order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :menu_item, null: false, foreign_key: true
      t.integer :quantity
      t.integer :unit_price_cents

      t.timestamps
    end
  end
end
