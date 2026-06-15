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

ActiveRecord::Schema[8.1].define(version: 2026_06_03_123001) do
  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.integer "port_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["port_id"], name: "index_comments_on_port_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "dependencies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dep_type"
    t.integer "depends_on_id"
    t.integer "port_id"
    t.datetime "updated_at", null: false
    t.index ["depends_on_id"], name: "index_dependencies_on_depends_on_id"
    t.index ["port_id"], name: "index_dependencies_on_port_id"
  end

  create_table "maintainers", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_maintainers_on_name", unique: true
  end

  create_table "port_updates", force: :cascade do |t|
    t.string "commit_id"
    t.text "commit_message"
    t.datetime "committed_at"
    t.datetime "created_at", null: false
    t.string "new_version"
    t.string "old_version"
    t.integer "port_id"
    t.datetime "updated_at", null: false
    t.index ["port_id"], name: "index_port_updates_on_port_id"
  end

  create_table "ports", force: :cascade do |t|
    t.integer "category_id"
    t.text "comment"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "homepage"
    t.date "last_updated"
    t.string "maintainer"
    t.integer "maintainer_id"
    t.string "name"
    t.boolean "permit_file_distfiles", default: false
    t.string "pkgpath"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["category_id"], name: "index_ports_on_category_id"
    t.index ["maintainer_id"], name: "index_ports_on_maintainer_id"
    t.index ["name"], name: "index_ports_on_name", unique: true
    t.index ["pkgpath"], name: "index_ports_on_pkgpath", unique: true
  end

  create_table "security_advisories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "cvss_score"
    t.text "description"
    t.string "identifier"
    t.integer "port_id"
    t.datetime "published_at"
    t.datetime "resolved_at"
    t.integer "severity", default: 1
    t.string "source_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["identifier"], name: "index_security_advisories_on_identifier", unique: true
    t.index ["port_id"], name: "index_security_advisories_on_port_id"
    t.index ["published_at"], name: "index_security_advisories_on_published_at"
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

  create_table "watches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "notify_on_update", default: true
    t.integer "port_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["port_id"], name: "index_watches_on_port_id"
    t.index ["user_id"], name: "index_watches_on_user_id"
  end

  add_foreign_key "comments", "ports"
  add_foreign_key "comments", "users"
  add_foreign_key "dependencies", "ports"
  add_foreign_key "dependencies", "ports", column: "depends_on_id"
  add_foreign_key "port_updates", "ports"
  add_foreign_key "ports", "categories"
  add_foreign_key "ports", "maintainers"
  add_foreign_key "security_advisories", "ports"
  add_foreign_key "sessions", "users"
  add_foreign_key "watches", "ports"
  add_foreign_key "watches", "users"
end
