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

ActiveRecord::Schema[8.1].define(version: 2026_11_02_150000) do
  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.string "email"
    t.string "plan_key", null: false
    t.string "status", null: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id", null: false
    t.string "token_digest"
    t.string "token_hint"
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.string "usage_period"
    t.index ["stripe_subscription_id"], name: "index_api_keys_on_stripe_subscription_id", unique: true
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "api_copy_reviews", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "creative_sha256", null: false
    t.integer "api_key_id", null: false
    t.json "finding_codes", default: [], null: false
    t.json "summary", default: {}, null: false
    t.string "product_sha256"
    t.integer "report_version", null: false
    t.string "request_id", null: false
    t.string "reviewer_sha256", null: false
    t.string "source_trust", default: "caller_supplied_unverified", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key_id", "created_at"], name: "index_api_copy_reviews_on_api_key_id_and_created_at"
    t.index ["api_key_id"], name: "index_api_copy_reviews_on_api_key_id"
    t.index ["request_id"], name: "index_api_copy_reviews_on_request_id", unique: true
  end

  add_foreign_key "api_copy_reviews", "api_keys"
end
