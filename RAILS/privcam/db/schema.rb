# frozen_string_literal: true

ActiveRecord::Schema[8.1].define(version: 2026_07_09_120000) do
  create_table "comments", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "video_id", null: false
    t.index ["user_id"], name: "index_comments_on_user_id"
    t.index ["video_id"], name: "index_comments_on_video_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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

  create_table "videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_videos_on_user_id"
  end

  add_foreign_key "comments", "users"
  add_foreign_key "comments", "videos"
  add_foreign_key "sessions", "users"
  add_foreign_key "videos", "users"
end