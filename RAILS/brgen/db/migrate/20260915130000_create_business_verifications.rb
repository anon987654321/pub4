# frozen_string_literal: true

# A business asks to be shown as verified, and a person decides. The request
# names the business by type and id, because the same review covers a
# marketplace store and a takeaway restaurant, and the verdict is denormalised
# onto the business so a card reads one column rather than joining a queue.
#
# marketplace_stores.verified already existed with no writer; this is its
# writer. takeaway_restaurants gains the same column.
class CreateBusinessVerifications < ActiveRecord::Migration[8.1]
  def change
    create_table :business_verifications do |t|
      t.string :business_type, null: false
      t.integer :business_id, null: false
      t.references :requested_by, null: false, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.string :legal_name, null: false
      t.string :organisation_number, null: false, limit: 9
      t.string :status, null: false, default: "pending"
      t.datetime :reviewed_at
      t.text :review_note
      t.timestamps
    end
    add_index :business_verifications, %i[business_type business_id status], name: "index_business_verifications_on_business_and_status"

    add_column :takeaway_restaurants, :verified, :boolean, default: false, null: false
  end
end
