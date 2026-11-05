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

ActiveRecord::Schema[8.2].define(version: 2026_11_05_130000) do
  create_table "cart_items", force: :cascade do |t|
    t.integer "cart_id", null: false
    t.integer "menu_item_id", null: false
    t.integer "quantity", default: 1, null: false
    t.string "option_ids"
    t.string "note"
    t.integer "unit_price_ore", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["cart_id", "menu_item_id"], name: "index_cart_items_on_cart_id_and_menu_item_id"
    t.index ["cart_id"], name: "index_cart_items_on_cart_id"
    t.index ["menu_item_id"], name: "index_cart_items_on_menu_item_id"
  end

  create_table "carts", force: :cascade do |t|
    t.integer "user_id"
    t.string "session_key"
    t.string "delivery_mode", default: "delivery", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "checkout_started_at"
    t.index ["session_key"], name: "index_carts_on_session_key"
    t.index ["user_id"], name: "index_carts_on_user_id"
  end

  create_table "delivery_zones", force: :cascade do |t|
    t.string "postcode", null: false
    t.string "name", null: false
    t.integer "fee_ore", null: false
    t.integer "min_basket_ore", null: false
    t.integer "eta_minutes", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["postcode"], name: "index_delivery_zones_on_postcode", unique: true
  end

  create_table "item_options", force: :cascade do |t|
    t.integer "menu_item_id", null: false
    t.string "name", null: false
    t.string "name_en"
    t.integer "price_ore", default: 0, null: false
    t.string "kind", null: false
    t.boolean "default_on", default: false, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["menu_item_id", "position"], name: "index_item_options_on_menu_item_id_and_position"
    t.index ["menu_item_id"], name: "index_item_options_on_menu_item_id"
  end

  create_table "kitchens", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "address"
    t.string "postcode"
    t.string "phone"
    t.string "opening_hours"
    t.float "rating", default: 4.9, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "opening_hours_en"
    t.json "weekly_hours"
    t.index ["slug"], name: "index_kitchens_on_slug", unique: true
  end

  create_table "loyalty_stamps", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "order_id"
    t.boolean "redeemed", default: false, null: false
    t.datetime "awarded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "redeemed_order_id"
    t.index ["order_id"], name: "index_loyalty_stamps_on_order_id"
    t.index ["redeemed_order_id"], name: "index_loyalty_stamps_on_redeemed_order_id"
    t.index ["user_id", "redeemed"], name: "index_loyalty_stamps_on_user_id_and_redeemed"
    t.index ["user_id"], name: "index_loyalty_stamps_on_user_id"
  end

  create_table "menu_categories", force: :cascade do |t|
    t.integer "kitchen_id", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "slug", null: false
    t.string "emoji"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kitchen_id", "position"], name: "index_menu_categories_on_kitchen_id_and_position"
    t.index ["kitchen_id"], name: "index_menu_categories_on_kitchen_id"
    t.index ["slug"], name: "index_menu_categories_on_slug", unique: true
  end

  create_table "menu_items", force: :cascade do |t|
    t.integer "menu_category_id", null: false
    t.string "name", null: false
    t.string "name_en"
    t.string "description"
    t.string "description_en"
    t.integer "price_ore", null: false
    t.string "origin"
    t.string "emoji"
    t.integer "heat", default: 0, null: false
    t.string "badges"
    t.integer "weight_g"
    t.integer "position"
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "photo_path"
    t.string "allergens"
    t.index ["available"], name: "index_menu_items_on_available"
    t.index ["menu_category_id", "position"], name: "index_menu_items_on_menu_category_id_and_position"
    t.index ["menu_category_id"], name: "index_menu_items_on_menu_category_id"
    t.index ["position"], name: "index_menu_items_on_position"
  end

  create_table "order_items", force: :cascade do |t|
    t.integer "order_id", null: false
    t.integer "menu_item_id"
    t.string "name", null: false
    t.string "emoji"
    t.integer "quantity", default: 1, null: false
    t.integer "unit_price_ore", null: false
    t.string "options_text"
    t.integer "line_total_ore", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "note"
    t.index ["menu_item_id"], name: "index_order_items_on_menu_item_id"
    t.index ["order_id"], name: "index_order_items_on_order_id"
  end

  create_table "orders", force: :cascade do |t|
    t.integer "user_id"
    t.integer "kitchen_id", null: false
    t.string "state", default: "placed", null: false
    t.string "delivery_mode"
    t.string "address"
    t.string "postcode"
    t.string "phone"
    t.integer "subtotal_ore"
    t.integer "delivery_fee_ore"
    t.integer "discount_ore", default: 0, null: false
    t.integer "tip_ore", default: 0, null: false
    t.integer "total_ore"
    t.string "promo_code"
    t.integer "eta_minutes"
    t.string "tracking_token", null: false
    t.string "payment_state", default: "pending", null: false
    t.string "vipps_order_id"
    t.string "vipps_url"
    t.integer "payment_steps", default: 3, null: false
    t.boolean "express", default: true, null: false
    t.datetime "placed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "external_delivery_id"
    t.string "external_delivery_url"
    t.string "payment_method", default: "vipps", null: false
    t.integer "cart_id"
    t.string "courier_name"
    t.string "customer_name"
    t.string "delivery_note"
    t.datetime "confirmed_at"
    t.datetime "ready_at"
    t.datetime "picked_up_at"
    t.datetime "delivered_at"
    t.string "refund_state"
    t.index ["cart_id"], name: "index_orders_on_cart_id"
    t.index ["kitchen_id"], name: "index_orders_on_kitchen_id"
    t.index ["payment_method"], name: "index_orders_on_payment_method"
    t.index ["payment_state"], name: "index_orders_on_payment_state"
    t.index ["state"], name: "index_orders_on_state"
    t.index ["tracking_token"], name: "index_orders_on_tracking_token", unique: true
    t.index ["user_id", "state"], name: "index_orders_on_user_id_and_state"
    t.index ["user_id"], name: "index_orders_on_user_id"
  end

  create_table "promo_codes", force: :cascade do |t|
    t.string "code", null: false
    t.string "kind", null: false
    t.integer "value"
    t.integer "min_basket_ore", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_promo_codes_on_code", unique: true
  end

  create_table "reviews", force: :cascade do |t|
    t.integer "order_id", null: false
    t.integer "user_id", null: false
    t.integer "rating", null: false
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id", "user_id"], name: "index_reviews_on_order_id_and_user_id", unique: true
    t.index ["order_id"], name: "index_reviews_on_order_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "phone", null: false
    t.string "name"
    t.integer "role", default: 0, null: false
    t.string "default_address"
    t.string "default_postcode"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["phone"], name: "index_users_on_phone", unique: true
  end

  add_foreign_key "cart_items", "carts"
  add_foreign_key "cart_items", "menu_items"
  add_foreign_key "carts", "users"
  add_foreign_key "item_options", "menu_items"
  add_foreign_key "loyalty_stamps", "orders"
  add_foreign_key "loyalty_stamps", "orders", column: "redeemed_order_id"
  add_foreign_key "loyalty_stamps", "users"
  add_foreign_key "menu_categories", "kitchens"
  add_foreign_key "menu_items", "menu_categories"
  add_foreign_key "order_items", "orders"
  add_foreign_key "orders", "kitchens"
  add_foreign_key "orders", "users"
  add_foreign_key "reviews", "orders"
  add_foreign_key "reviews", "users"
  add_foreign_key "sessions", "users"
end
