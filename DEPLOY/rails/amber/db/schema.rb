# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_25_000100) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "affiliate_links", force: :cascade do |t|
    t.decimal "commission_rate", precision: 8, scale: 4
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.string "merchant", null: false
    t.json "metadata"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["item_id"], name: "index_affiliate_links_on_item_id"
  end

  create_table "consent_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.json "metadata"
    t.string "purpose", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_consent_events_on_user_id"
  end

  create_table "creator_profiles", force: :cascade do |t|
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "handle", null: false
    t.json "links"
    t.boolean "public", default: false, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["handle"], name: "index_creator_profiles_on_handle", unique: true
    t.index ["user_id"], name: "index_creator_profiles_on_user_id", unique: true
  end

  create_table "creator_wardrobe_items", force: :cascade do |t|
    t.string "caption"
    t.datetime "created_at", null: false
    t.integer "creator_profile_id", null: false
    t.integer "item_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["creator_profile_id", "item_id"], name: "index_creator_wardrobe_items_on_creator_profile_id_and_item_id", unique: true
    t.index ["creator_profile_id"], name: "index_creator_wardrobe_items_on_creator_profile_id"
    t.index ["item_id"], name: "index_creator_wardrobe_items_on_item_id"
  end

  create_table "declutter_challenges", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.date "due_on", null: false
    t.integer "item_id", null: false
    t.json "metadata"
    t.string "note"
    t.integer "outfit_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["item_id"], name: "index_declutter_challenges_on_item_id"
    t.index ["outfit_id"], name: "index_declutter_challenges_on_outfit_id"
    t.index ["user_id", "status", "due_on"], name: "index_declutter_challenges_on_user_id_and_status_and_due_on"
    t.index ["user_id"], name: "index_declutter_challenges_on_user_id"
  end

  create_table "declutter_outcomes", force: :cascade do |t|
    t.string "action", null: false
    t.integer "amount_recovered_cents"
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.json "metadata"
    t.text "notes"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["item_id"], name: "index_declutter_outcomes_on_item_id"
    t.index ["user_id", "action", "created_at"], name: "index_declutter_outcomes_on_user_id_and_action_and_created_at"
    t.index ["user_id"], name: "index_declutter_outcomes_on_user_id"
  end

  create_table "declutter_reviews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "decision"
    t.integer "item_id", null: false
    t.json "metadata"
    t.text "notes"
    t.string "reason_kept"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["item_id"], name: "index_declutter_reviews_on_item_id"
    t.index ["user_id", "item_id"], name: "index_declutter_reviews_on_user_id_and_item_id", unique: true
    t.index ["user_id"], name: "index_declutter_reviews_on_user_id"
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "followee_id", null: false
    t.integer "follower_id", null: false
    t.datetime "updated_at", null: false
    t.index ["followee_id"], name: "index_follows_on_followee_id"
    t.index ["follower_id"], name: "index_follows_on_follower_id"
  end

  create_table "garment_embeddings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "dimensions"
    t.integer "item_id", null: false
    t.json "metadata"
    t.string "model", null: false
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.json "vector"
    t.index ["item_id"], name: "index_garment_embeddings_on_item_id", unique: true
  end

  create_table "identity_verifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "human", null: false
    t.json "metadata"
    t.datetime "reviewed_at"
    t.string "reviewer"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_identity_verifications_on_user_id"
  end

  create_table "items", force: :cascade do |t|
    t.string "analysis_status"
    t.string "brand"
    t.string "category"
    t.string "color"
    t.datetime "created_at", null: false
    t.date "last_worn_on"
    t.string "life_phase"
    t.string "lifecycle_state", default: "active", null: false
    t.string "material"
    t.json "metadata"
    t.string "mood_effect"
    t.string "occasion_tags"
    t.integer "price_cents"
    t.date "purchase_date"
    t.string "season"
    t.string "size"
    t.boolean "spark_joy"
    t.integer "times_worn"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "outfit_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.integer "outfit_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_outfit_items_on_item_id"
    t.index ["outfit_id"], name: "index_outfit_items_on_outfit_id"
  end

  create_table "outfits", force: :cascade do |t|
    t.string "category"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "likes_count"
    t.string "name"
    t.string "occasion"
    t.string "season"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_outfits_on_user_id"
  end

  create_table "packing_list_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.boolean "packed", default: false, null: false
    t.integer "packing_list_id", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_packing_list_items_on_item_id"
    t.index ["packing_list_id", "item_id"], name: "index_packing_list_items_on_packing_list_id_and_item_id", unique: true
    t.index ["packing_list_id"], name: "index_packing_list_items_on_packing_list_id"
  end

  create_table "packing_lists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "destination"
    t.date "ends_on", null: false
    t.string "name", null: false
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.json "weather_context"
    t.index ["user_id"], name: "index_packing_lists_on_user_id"
  end

  create_table "planned_outfits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "outfit_id", null: false
    t.date "planned_date"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["outfit_id"], name: "index_planned_outfits_on_outfit_id"
    t.index ["user_id"], name: "index_planned_outfits_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.integer "likes_count"
    t.integer "outfit_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["item_id"], name: "index_posts_on_item_id"
    t.index ["outfit_id"], name: "index_posts_on_outfit_id"
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "privacy_settings", force: :cascade do |t|
    t.boolean "allow_ai_analysis", default: true, null: false
    t.boolean "allow_creator_remix", default: false, null: false
    t.string "analytics_visibility", default: "private", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "wardrobe_visibility", default: "private", null: false
    t.index ["user_id"], name: "index_privacy_settings_on_user_id", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.text "bio"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "location"
    t.json "style_summary"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "visibility", default: "private", null: false
    t.index ["user_id"], name: "index_profiles_on_user_id", unique: true
  end

  create_table "recommendations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.integer "item_id"
    t.string "kind", null: false
    t.json "metadata"
    t.integer "outfit_id"
    t.text "reason", null: false
    t.decimal "score", precision: 8, scale: 4
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["item_id"], name: "index_recommendations_on_item_id"
    t.index ["outfit_id"], name: "index_recommendations_on_outfit_id"
    t.index ["user_id", "kind", "dismissed_at"], name: "index_recommendations_on_user_id_and_kind_and_dismissed_at"
    t.index ["user_id"], name: "index_recommendations_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "style_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "aesthetic", null: false
    t.json "metadata"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.decimal "weight", precision: 8, scale: 4, default: "1.0", null: false
    t.index ["user_id", "kind", "name"], name: "index_style_preferences_on_user_id_and_kind_and_name", unique: true
    t.index ["user_id"], name: "index_style_preferences_on_user_id"
  end

  create_table "sustainability_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "environmental_score", precision: 8, scale: 2
    t.integer "item_id", null: false
    t.json "metadata"
    t.integer "repair_cost_estimate_cents"
    t.integer "resale_value_cents"
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_sustainability_metrics_on_item_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "wear_logs", force: :cascade do |t|
    t.string "context"
    t.datetime "created_at", null: false
    t.integer "item_id", null: false
    t.json "metadata"
    t.integer "outfit_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.date "worn_on", null: false
    t.index ["item_id"], name: "index_wear_logs_on_item_id"
    t.index ["outfit_id"], name: "index_wear_logs_on_outfit_id"
    t.index ["user_id"], name: "index_wear_logs_on_user_id"
    t.index ["worn_on"], name: "index_wear_logs_on_worn_on"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "affiliate_links", "items"
  add_foreign_key "consent_events", "users"
  add_foreign_key "creator_profiles", "users"
  add_foreign_key "creator_wardrobe_items", "creator_profiles"
  add_foreign_key "creator_wardrobe_items", "items"
  add_foreign_key "declutter_challenges", "items"
  add_foreign_key "declutter_challenges", "outfits"
  add_foreign_key "declutter_challenges", "users"
  add_foreign_key "declutter_outcomes", "items"
  add_foreign_key "declutter_outcomes", "users"
  add_foreign_key "declutter_reviews", "items"
  add_foreign_key "declutter_reviews", "users"
  add_foreign_key "follows", "users", column: "followee_id"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "garment_embeddings", "items"
  add_foreign_key "identity_verifications", "users"
  add_foreign_key "items", "users"
  add_foreign_key "outfit_items", "items"
  add_foreign_key "outfit_items", "outfits"
  add_foreign_key "outfits", "users"
  add_foreign_key "packing_list_items", "items"
  add_foreign_key "packing_list_items", "packing_lists"
  add_foreign_key "packing_lists", "users"
  add_foreign_key "planned_outfits", "outfits"
  add_foreign_key "planned_outfits", "users"
  add_foreign_key "posts", "items"
  add_foreign_key "posts", "outfits"
  add_foreign_key "posts", "users"
  add_foreign_key "privacy_settings", "users"
  add_foreign_key "profiles", "users"
  add_foreign_key "recommendations", "items"
  add_foreign_key "recommendations", "outfits"
  add_foreign_key "recommendations", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "style_preferences", "users"
  add_foreign_key "sustainability_metrics", "items"
  add_foreign_key "wear_logs", "items"
  add_foreign_key "wear_logs", "outfits"
  add_foreign_key "wear_logs", "users"
end
