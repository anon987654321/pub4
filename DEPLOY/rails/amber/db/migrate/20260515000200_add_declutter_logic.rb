class AddDeclutterLogic < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :lifecycle_state, :string, null: false, default: "active" unless column_exists?(:items, :lifecycle_state)
    add_column :items, :last_worn_on, :date unless column_exists?(:items, :last_worn_on)

    create_table :declutter_reviews do |t|
      t.references :user, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.string :reason_kept
      t.string :decision
      t.text :notes
      t.json :metadata
      t.timestamps
    end
    add_index :declutter_reviews, %i[user_id item_id], unique: true

    create_table :declutter_challenges do |t|
      t.references :user, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.references :outfit, foreign_key: true
      t.date :due_on, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at
      t.string :note
      t.json :metadata
      t.timestamps
    end
    add_index :declutter_challenges, %i[user_id status due_on]

    create_table :declutter_outcomes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.string :action, null: false
      t.decimal :amount_recovered, precision: 10, scale: 2
      t.text :notes
      t.json :metadata
      t.timestamps
    end
    add_index :declutter_outcomes, %i[user_id action created_at]
  end
end
