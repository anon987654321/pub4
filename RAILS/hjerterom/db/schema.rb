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

ActiveRecord::Schema[8.1].define(version: 2026_07_09_120000) do
  create_table "beneficiaries", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.string "area"
    t.float "latitude"
    t.float "longitude"
    t.datetime "created_at", null: false
    t.text "dietary_restrictions"
    t.integer "household_size"
    t.string "name", null: false
    t.text "notes"
    t.integer "priority", default: 0, null: false
    t.datetime "updated_at", null: false
  end

  create_table "boxes", force: :cascade do |t|
    t.integer "beneficiary_id"
    t.datetime "created_at", null: false
    t.text "notes"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.date "week_start", null: false
    t.index ["beneficiary_id"], name: "index_boxes_on_beneficiary_id"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.string "slug"
    t.string "type_of"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.boolean "anonymous", default: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.integer "post_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["post_id"], name: "index_comments_on_post_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "crises", force: :cascade do |t|
    t.boolean "available_24h", default: false
    t.string "chat_url"
    t.string "country"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "languages"
    t.string "phone"
    t.string "sms"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "donations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "donor_id"
    t.text "notes"
    t.string "pickup_window"
    t.string "source_name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["donor_id"], name: "index_donations_on_donor_id"
  end

  create_table "delivery_routes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.date "route_date", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "volunteer_id"
    t.index ["volunteer_id"], name: "index_delivery_routes_on_volunteer_id"
  end

  create_table "delivery_stops", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "delivery_route_id", null: false
    t.float "latitude"
    t.float "longitude"
    t.string "label", null: false
    t.bigint "reference_id"
    t.string "reference_type"
    t.integer "sequence", default: 0, null: false
    t.integer "stop_kind", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_route_id"], name: "index_delivery_stops_on_delivery_route_id"
    t.index ["reference_type", "reference_id"], name: "index_delivery_stops_on_reference_type_and_reference_id"
  end

  create_table "donors", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "address"
    t.datetime "created_at", null: false
    t.string "email"
    t.float "latitude"
    t.float "longitude"
    t.string "name", null: false
    t.text "notes"
    t.string "phone"
    t.datetime "updated_at", null: false
  end

  create_table "food_items", force: :cascade do |t|
    t.string "age_range"
    t.integer "beneficiary_id"
    t.date "best_before"
    t.integer "box_id"
    t.integer "category", default: 6, null: false
    t.string "condition_label"
    t.datetime "created_at", null: false
    t.text "dietary_tags"
    t.integer "donation_id", null: false
    t.string "language_label"
    t.string "name", null: false
    t.text "notes"
    t.integer "quality_state", default: 0, null: false
    t.integer "quantity"
    t.string "reuse_status", default: "intake", null: false
    t.string "size_label"
    t.string "status", default: "available", null: false
    t.datetime "updated_at", null: false
    t.index ["beneficiary_id"], name: "index_food_items_on_beneficiary_id"
    t.index ["box_id"], name: "index_food_items_on_box_id"
    t.index ["donation_id"], name: "index_food_items_on_donation_id"
  end

  create_table "food_listings", force: :cascade do |t|
    t.datetime "available_from"
    t.datetime "available_until"
    t.string "city"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "dietary_info"
    t.float "latitude"
    t.float "longitude"
    t.string "pickup_address"
    t.integer "quantity"
    t.string "status"
    t.string "title"
    t.string "unit"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_food_listings_on_user_id"
  end

  create_table "food_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "food_listing_id"
    t.text "message"
    t.datetime "pickup_time"
    t.string "status"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["food_listing_id"], name: "index_food_requests_on_food_listing_id"
    t.index ["user_id"], name: "index_food_requests_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.boolean "anonymous", default: false
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.boolean "pinned", default: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "views_count", default: 0
    t.index ["category_id"], name: "index_posts_on_category_id"
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "resources", force: :cascade do |t|
    t.string "address"
    t.integer "category_id"
    t.string "city"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "email"
    t.float "latitude"
    t.float "longitude"
    t.text "opening_hours"
    t.string "phone"
    t.string "postal_code"
    t.string "resource_type"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id"
    t.boolean "verified", default: false
    t.index ["category_id"], name: "index_resources_on_category_id"
    t.index ["user_id"], name: "index_resources_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "shifts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.integer "kind", default: 1, null: false
    t.string "location"
    t.text "notes"
    t.datetime "starts_at", null: false
    t.integer "state", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "volunteer_id"
    t.index ["volunteer_id"], name: "index_shifts_on_volunteer_id"
  end

  create_table "support_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "priority"
    t.datetime "resolved_at"
    t.string "status"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_support_requests_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "remember_token"
    t.datetime "remember_token_expires_at"
    t.string "magic_link_token"
    t.datetime "magic_link_expires_at"
    t.datetime "deletion_scheduled_at"
    t.datetime "deleted_at"
    t.string "otp_secret"
    t.boolean "two_factor_enabled", default: false, null: false
    t.index ["remember_token"], name: "index_users_on_remember_token", unique: true
    t.index ["magic_link_token"], name: "index_users_on_magic_link_token", unique: true
    t.index ["deletion_scheduled_at"], name: "index_users_on_deletion_scheduled_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "volunteers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.text "notes"
    t.string "phone"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_volunteers_on_user_id"
  end

  add_foreign_key "boxes", "beneficiaries"
  add_foreign_key "delivery_routes", "volunteers"
  add_foreign_key "delivery_stops", "delivery_routes"
  add_foreign_key "comments", "posts"
  add_foreign_key "comments", "users"
  add_foreign_key "donations", "donors"
  add_foreign_key "food_items", "beneficiaries"
  add_foreign_key "food_items", "boxes"
  add_foreign_key "food_items", "donations"
  add_foreign_key "food_listings", "users"
  add_foreign_key "food_requests", "food_listings"
  add_foreign_key "food_requests", "users"
  add_foreign_key "posts", "categories"
  add_foreign_key "posts", "users"
  add_foreign_key "resources", "categories"
  add_foreign_key "resources", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "shifts", "volunteers"
  add_foreign_key "support_requests", "users"
  add_foreign_key "volunteers", "users"
end
