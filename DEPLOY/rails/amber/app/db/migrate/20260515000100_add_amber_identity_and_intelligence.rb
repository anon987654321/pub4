class AddAmberIdentityAndIntelligence < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :display_name
      t.text :bio
      t.string :location
      t.string :visibility, null: false, default: "private"
      t.json :style_summary
      t.timestamps
    end

    create_table :privacy_settings do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :wardrobe_visibility, null: false, default: "private"
      t.string :analytics_visibility, null: false, default: "private"
      t.boolean :allow_ai_analysis, null: false, default: true
      t.boolean :allow_creator_remix, null: false, default: false
      t.timestamps
    end

    create_table :creator_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :handle, null: false
      t.string :display_name, null: false
      t.text :bio
      t.boolean :public, null: false, default: false
      t.json :links
      t.timestamps
    end
    add_index :creator_profiles, :handle, unique: true

    create_table :creator_wardrobe_items do |t|
      t.references :creator_profile, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.string :caption
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :creator_wardrobe_items, %i[creator_profile_id item_id], unique: true

    create_table :garment_embeddings do |t|
      t.references :item, null: false, foreign_key: true, index: { unique: true }
      t.string :provider, null: false
      t.string :model, null: false
      t.integer :dimensions
      t.json :vector
      t.json :metadata
      t.timestamps
    end

    create_table :wear_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.references :outfit, foreign_key: true
      t.date :worn_on, null: false
      t.string :context
      t.json :metadata
      t.timestamps
    end
    add_index :wear_logs, :worn_on

    create_table :sustainability_metrics do |t|
      t.references :item, null: false, foreign_key: true, index: { unique: true }
      t.decimal :resale_value, precision: 10, scale: 2
      t.decimal :repair_cost_estimate, precision: 10, scale: 2
      t.decimal :environmental_score, precision: 8, scale: 2
      t.json :metadata
      t.timestamps
    end

    create_table :affiliate_links do |t|
      t.references :item, null: false, foreign_key: true
      t.string :merchant, null: false
      t.string :url, null: false
      t.decimal :commission_rate, precision: 8, scale: 4
      t.json :metadata
      t.timestamps
    end

    create_table :style_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false, default: "aesthetic"
      t.string :name, null: false
      t.decimal :weight, precision: 8, scale: 4, null: false, default: 1.0
      t.json :metadata
      t.timestamps
    end
    add_index :style_preferences, %i[user_id kind name], unique: true

    create_table :recommendations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :item, foreign_key: true
      t.references :outfit, foreign_key: true
      t.string :kind, null: false
      t.text :reason, null: false
      t.decimal :score, precision: 8, scale: 4
      t.datetime :dismissed_at
      t.json :metadata
      t.timestamps
    end
    add_index :recommendations, %i[user_id kind dismissed_at]

    create_table :packing_lists do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :destination
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.json :weather_context
      t.timestamps
    end

    create_table :packing_list_items do |t|
      t.references :packing_list, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.boolean :packed, null: false, default: false
      t.timestamps
    end
    add_index :packing_list_items, %i[packing_list_id item_id], unique: true

    create_table :identity_verifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false, default: "human"
      t.string :status, null: false, default: "pending"
      t.string :reviewer
      t.datetime :reviewed_at
      t.json :metadata
      t.timestamps
    end

    create_table :consent_events do |t|
      t.references :user, null: false, foreign_key: true
      t.string :purpose, null: false
      t.string :decision, null: false
      t.json :metadata
      t.timestamps
    end

    add_column :items, :analysis_status, :string unless column_exists?(:items, :analysis_status)
    add_column :items, :metadata, :json unless column_exists?(:items, :metadata)
  end
end
