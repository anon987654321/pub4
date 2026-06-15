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

ActiveRecord::Schema[8.1].define(version: 2026_06_15_000001) do
  create_table "bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "verse_id"
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
    t.index ["verse_id"], name: "index_bookmarks_on_verse_id"
  end

  create_table "books", force: :cascade do |t|
    t.string "abbreviation"
    t.integer "chapter_count"
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "order_index"
    t.string "testament"
    t.string "tradition"
    t.datetime "updated_at", null: false
    t.index ["tradition"], name: "index_books_on_tradition"
  end

  create_table "chapters", force: :cascade do |t|
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.integer "number"
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_chapters_on_book_id"
  end

  create_table "cross_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind"
    t.text "note"
    t.integer "target_verse_id", null: false
    t.datetime "updated_at", null: false
    t.integer "verse_id", null: false
    t.index ["target_verse_id"], name: "index_cross_references_on_target_verse_id"
    t.index ["verse_id", "target_verse_id"], name: "index_cross_references_on_verse_id_and_target_verse_id", unique: true
    t.index ["verse_id"], name: "index_cross_references_on_verse_id"
  end

  create_table "highlights", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.text "note"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "verse_id"
    t.index ["user_id"], name: "index_highlights_on_user_id"
    t.index ["verse_id"], name: "index_highlights_on_verse_id"
  end

  create_table "reading_plan_days", force: :cascade do |t|
    t.integer "book_id"
    t.integer "chapter_end"
    t.integer "chapter_start"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "day_number"
    t.integer "reading_plan_id"
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_reading_plan_days_on_book_id"
    t.index ["reading_plan_id"], name: "index_reading_plan_days_on_reading_plan_id"
  end

  create_table "reading_plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_days"
    t.string "name"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_reading_plans_on_user_id"
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
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "verses", force: :cascade do |t|
    t.integer "book_id"
    t.integer "chapter_id"
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "number"
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_verses_on_book_id"
    t.index ["chapter_id"], name: "index_verses_on_chapter_id"
  end

  create_table "word_studies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "definition"
    t.string "language"
    t.string "original"
    t.integer "position", null: false
    t.string "strongs"
    t.string "transliteration"
    t.datetime "updated_at", null: false
    t.integer "verse_id", null: false
    t.string "word", null: false
    t.index ["verse_id", "position"], name: "index_word_studies_on_verse_id_and_position", unique: true
    t.index ["verse_id"], name: "index_word_studies_on_verse_id"
  end

  add_foreign_key "bookmarks", "users"
  add_foreign_key "bookmarks", "verses"
  add_foreign_key "chapters", "books"
  add_foreign_key "cross_references", "verses"
  add_foreign_key "cross_references", "verses", column: "target_verse_id"
  add_foreign_key "highlights", "users"
  add_foreign_key "highlights", "verses"
  add_foreign_key "reading_plan_days", "books"
  add_foreign_key "reading_plan_days", "reading_plans"
  add_foreign_key "reading_plans", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "verses", "books"
  add_foreign_key "verses", "chapters"
  add_foreign_key "word_studies", "verses"
end
