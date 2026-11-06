# frozen_string_literal: true

# Size and colour as rows, not as a column.
#
# `marketplace_listings.stock` says how many of *the listing* are left, which is
# the right answer for a bike and the wrong one for a shirt that exists in four
# sizes: the shop either lists the same shirt four times or oversells the medium.
# A variant is the thing actually bought, so it carries its own price and its own
# stock, and the option rows say what makes it different.
class CreateMarketplaceVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :marketplace_variants do |t|
      t.references :listing, null: false, foreign_key: { to_table: :marketplace_listings }
      # Both nullable and both meaning "inherit the listing": a shop that varies
      # only the size should not have to restate the price four times, and
      # restating it is how the two drift apart.
      t.integer :price_cents
      t.integer :stock
      t.string :sku
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # Any number of axes, queryable — "which variants are blue" is a where, not a
    # LIKE against a label. Two axes is what size/colour needs; the schema does
    # not have to care.
    create_table :marketplace_variant_options do |t|
      t.references :variant, null: false, foreign_key: { to_table: :marketplace_variants }
      t.string :name, null: false
      t.string :value, null: false
      t.timestamps
    end

    add_index :marketplace_variant_options, %i[variant_id name], unique: true
    add_index :marketplace_variant_options, %i[name value]

    # Which variant an order is for. Nullable: a listing with no variants is the
    # classifieds case, and that is most of them.
    add_reference :marketplace_orders, :variant, null: true, foreign_key: { to_table: :marketplace_variants }
  end
end
