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

ActiveRecord::Schema[8.1].define(version: 2026_08_17_000000) do
  create_table "account_merges", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "guest_user_id", null: false
    t.datetime "merged_at"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["guest_user_id", "user_id"], name: "index_account_merges_on_guest_user_id_and_user_id", unique: true
    t.index ["guest_user_id"], name: "index_account_merges_on_guest_user_id"
    t.index ["user_id"], name: "index_account_merges_on_user_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "blurhash"
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
    t.integer "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activity_events", force: :cascade do |t|
    t.integer "actor_id"
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.string "locality"
    t.json "metadata"
    t.string "moderation_state", default: "clean", null: false
    t.integer "object_id", null: false
    t.string "object_type", null: false
    t.string "source_vertical", null: false
    t.datetime "updated_at", null: false
    t.string "visibility", default: "public", null: false
    t.index ["actor_id"], name: "index_activity_events_on_actor_id"
    t.index ["locality", "created_at"], name: "index_activity_events_on_locality_and_created_at"
    t.index ["object_type", "object_id"], name: "index_activity_events_on_object_type_and_object_id"
    t.index ["source_vertical", "created_at"], name: "index_activity_events_on_source_vertical_and_created_at"
  end

  create_table "affiliate_conversions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 8
    t.string "epi", limit: 500
    t.string "epi2", limit: 500
    t.integer "event_type_id"
    t.string "legacy_transaction_id", limit: 128
    t.integer "message_type_id", null: false
    t.string "order_number", limit: 128
    t.decimal "order_value", precision: 12, scale: 2
    t.string "product_id", limit: 128
    t.string "product_name", limit: 300
    t.integer "program_id"
    t.decimal "publisher_commission", precision: 12, scale: 2
    t.json "raw_payload"
    t.string "sequence_number", limit: 64
    t.integer "site_id"
    t.string "site_name", limit: 200
    t.string "source", limit: 32, default: "tradedoubler", null: false
    t.datetime "time_of_event"
    t.datetime "time_of_visit"
    t.string "transaction_id", limit: 128
    t.datetime "updated_at", null: false
    t.string "visitor_id", limit: 128
    t.index ["created_at"], name: "index_affiliate_conversions_on_created_at"
    t.index ["epi"], name: "index_affiliate_conversions_on_epi"
    t.index ["message_type_id"], name: "index_affiliate_conversions_on_message_type_id"
    t.index ["order_number"], name: "index_affiliate_conversions_on_order_number"
    t.index ["source", "transaction_id", "message_type_id"], name: "index_affiliate_conversions_on_source_txn_message", unique: true
  end

  create_table "affiliate_products", force: :cascade do |t|
    t.string "category", limit: 120
    t.text "click_url", null: false
    t.decimal "commission_rate", precision: 6, scale: 3
    t.datetime "created_at", null: false
    t.string "currency", limit: 8
    t.text "description"
    t.string "external_id", limit: 128, null: false
    t.text "image_url"
    t.boolean "in_stock", default: true, null: false
    t.datetime "last_seen_at"
    t.string "market", limit: 8
    t.string "merchant", limit: 200
    t.boolean "placeholder", default: false, null: false
    t.integer "price_cents"
    t.string "program_id", limit: 64
    t.string "source", limit: 32, null: false
    t.string "title", limit: 300, null: false
    t.datetime "updated_at", null: false
    t.index ["last_seen_at"], name: "index_affiliate_products_on_last_seen_at"
    t.index ["market", "category", "last_seen_at"], name: "index_affiliate_products_on_market_category_freshness"
    t.index ["source", "external_id"], name: "index_affiliate_products_on_source_and_external_id", unique: true
  end

  create_table "affiliate_vouchers", force: :cascade do |t|
    t.string "code", limit: 256
    t.datetime "created_at", null: false
    t.string "currency", limit: 8
    t.text "description"
    t.decimal "discount_amount", precision: 10, scale: 2
    t.datetime "ends_at"
    t.boolean "exclusive", default: false, null: false
    t.string "external_id", limit: 64, null: false
    t.text "landing_url"
    t.datetime "last_seen_at"
    t.string "market", limit: 8
    t.boolean "percentage", default: false, null: false
    t.string "program_id", limit: 64
    t.string "program_name", limit: 200
    t.string "short_description", limit: 200
    t.boolean "site_specific", default: false, null: false
    t.string "source", limit: 32, default: "tradedoubler", null: false
    t.datetime "starts_at"
    t.string "title", limit: 120, null: false
    t.text "track_url", null: false
    t.datetime "updated_at", null: false
    t.integer "voucher_type_id", default: 1, null: false
    t.index ["market", "ends_at"], name: "index_affiliate_vouchers_on_market_and_ends_at"
    t.index ["site_specific"], name: "index_affiliate_vouchers_on_site_specific"
    t.index ["source", "external_id"], name: "index_affiliate_vouchers_on_source_and_external_id", unique: true
  end

  create_table "anonymous_post_quotas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.integer "post_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_anonymous_post_quotas_on_fingerprint", unique: true
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.integer "actor_id"
    t.integer "context_id"
    t.string "context_type"
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.integer "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.index ["action", "occurred_at"], name: "index_audit_events_on_action_and_occurred_at"
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["context_type", "context_id", "occurred_at"], name: "idx_on_context_type_context_id_occurred_at_75c71d77bc"
    t.index ["target_type", "target_id"], name: "index_audit_events_on_target_type_and_target_id"
  end

  create_table "blocks", force: :cascade do |t|
    t.integer "blocked_id", null: false
    t.integer "blocker_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id"], name: "index_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_blocks_on_blocker_id"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["post_id"], name: "index_bookmarks_on_post_id"
    t.index ["user_id", "post_id"], name: "index_bookmarks_on_user_id_and_post_id", unique: true
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "cities", force: :cascade do |t|
    t.string "country_code", null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.string "domain", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.string "locale", null: false
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.string "slug", null: false
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.index ["domain"], name: "index_cities_on_domain", unique: true
    t.index ["slug"], name: "index_cities_on_slug", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.integer "commentable_id", null: false
    t.string "commentable_type", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.datetime "removed_at"
    t.datetime "summary_updated_at"
    t.text "thread_summary"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["parent_id"], name: "index_comments_on_parent_id"
    t.index ["removed_at"], name: "index_comments_on_removed_at"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "communities", force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "flairs"
    t.integer "members_count", default: 0, null: false
    t.string "name", null: false
    t.string "privacy", default: "public", null: false
    t.text "rules"
    t.string "slug"
    t.string "subdomain"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["city_id", "slug"], name: "index_communities_on_city_id_and_slug", unique: true
    t.index ["city_id"], name: "index_communities_on_city_id"
    t.index ["subdomain"], name: "index_communities_on_subdomain", unique: true
    t.index ["user_id"], name: "index_communities_on_user_id"
  end

  create_table "community_bans", force: :cascade do |t|
    t.integer "banned_by_id", null: false
    t.integer "community_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "reason"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["banned_by_id"], name: "index_community_bans_on_banned_by_id"
    t.index ["community_id", "user_id"], name: "index_community_bans_on_community_id_and_user_id", unique: true
    t.index ["community_id"], name: "index_community_bans_on_community_id"
    t.index ["user_id", "expires_at"], name: "index_community_bans_on_user_id_and_expires_at"
    t.index ["user_id"], name: "index_community_bans_on_user_id"
  end

  create_table "community_memberships", force: :cascade do |t|
    t.integer "community_id", null: false
    t.datetime "created_at", null: false
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["community_id", "role"], name: "index_community_memberships_on_community_id_and_role"
    t.index ["community_id"], name: "index_community_memberships_on_community_id"
    t.index ["user_id", "community_id"], name: "index_community_memberships_on_user_id_and_community_id", unique: true
    t.index ["user_id"], name: "index_community_memberships_on_user_id"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.integer "city_id"
    t.string "conversation_type"
    t.datetime "created_at", null: false
    t.integer "disappearing_duration"
    t.string "name"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.string "vertical"
    t.index ["city_id"], name: "index_conversations_on_city_id"
    t.index ["slug", "city_id"], name: "index_conversations_on_slug_and_city", unique: true
  end

  create_table "dating_dislikes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "dislikee_id", null: false
    t.integer "disliker_id", null: false
    t.datetime "updated_at", null: false
    t.index ["dislikee_id"], name: "index_dating_dislikes_on_dislikee_id"
    t.index ["disliker_id", "dislikee_id"], name: "index_dating_dislikes_on_disliker_id_and_dislikee_id", unique: true
    t.index ["disliker_id"], name: "index_dating_dislikes_on_disliker_id"
  end

  create_table "dating_likes", force: :cascade do |t|
    t.string "comment"
    t.datetime "created_at", null: false
    t.integer "dating_prompt_id"
    t.integer "likee_id", null: false
    t.integer "liker_id", null: false
    t.datetime "updated_at", null: false
    t.index ["dating_prompt_id"], name: "index_dating_likes_on_dating_prompt_id"
    t.index ["likee_id"], name: "index_dating_likes_on_likee_id"
    t.index ["liker_id", "likee_id"], name: "index_dating_likes_on_liker_id_and_likee_id", unique: true
    t.index ["liker_id"], name: "index_dating_likes_on_liker_id"
  end

  create_table "dating_matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "initiator_id", null: false
    t.integer "receiver_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["initiator_id", "receiver_id"], name: "index_dating_matches_on_initiator_id_and_receiver_id", unique: true
    t.index ["initiator_id"], name: "index_dating_matches_on_initiator_id"
    t.index ["receiver_id"], name: "index_dating_matches_on_receiver_id"
  end

  create_table "dating_profiles", force: :cascade do |t|
    t.integer "age"
    t.text "bio"
    t.string "bydel"
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.string "gender"
    t.datetime "last_active_at"
    t.decimal "latitude"
    t.string "location"
    t.decimal "longitude"
    t.string "looking_for"
    t.integer "neighborhood_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "visible"
    t.index ["city_id"], name: "index_dating_profiles_on_city_id"
    t.index ["neighborhood_id"], name: "index_dating_profiles_on_neighborhood_id"
    t.index ["user_id"], name: "index_dating_profiles_on_user_id"
    t.index ["visible", "last_active_at"], name: "index_dating_profiles_on_visible_and_last_active_at"
  end

  create_table "dating_prompts", force: :cascade do |t|
    t.string "answer", null: false
    t.datetime "created_at", null: false
    t.integer "position", default: 0, null: false
    t.integer "profile_id", null: false
    t.string "question", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_id", "position"], name: "index_dating_prompts_on_profile_id_and_position"
    t.index ["profile_id"], name: "index_dating_prompts_on_profile_id"
  end

  create_table "email_subscriptions", force: :cascade do |t|
    t.boolean "agreed_to_marketing", default: false, null: false
    t.string "city"
    t.boolean "confirmed", default: false, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.text "interests"
    t.string "locale"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_email_subscriptions_on_email", unique: true
    t.index ["token"], name: "index_email_subscriptions_on_token", unique: true
  end

  create_table "event_rsvps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.string "status", default: "going", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["event_id", "status"], name: "index_event_rsvps_on_event_id_and_status"
    t.index ["event_id", "user_id"], name: "index_event_rsvps_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_event_rsvps_on_event_id"
    t.index ["user_id"], name: "index_event_rsvps_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "address"
    t.datetime "cancelled_at"
    t.integer "capacity"
    t.integer "city_id"
    t.integer "comments_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "description"
    t.datetime "ends_at"
    t.string "external_url"
    t.integer "going_count", default: 0, null: false
    t.integer "interested_count", default: 0, null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.integer "neighborhood_id"
    t.integer "place_id"
    t.integer "price_cents"
    t.string "slug"
    t.datetime "starts_at", null: false
    t.string "status", default: "published", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "venue_name"
    t.index ["city_id", "slug"], name: "index_events_on_city_id_and_slug", unique: true
    t.index ["city_id", "status", "starts_at"], name: "index_events_on_city_id_and_status_and_starts_at"
    t.index ["city_id"], name: "index_events_on_city_id"
    t.index ["neighborhood_id"], name: "index_events_on_neighborhood_id"
    t.index ["place_id"], name: "index_events_on_place_id"
    t.index ["starts_at"], name: "index_events_on_starts_at"
    t.index ["user_id"], name: "index_events_on_user_id"
  end

  create_table "external_identities", force: :cascade do |t|
    t.string "assurance_level", default: "account", null: false
    t.datetime "created_at", null: false
    t.string "email_address"
    t.integer "identity_provider_id", null: false
    t.datetime "last_used_at"
    t.string "phone_number"
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["identity_provider_id", "subject"], name: "index_external_identities_on_provider_and_subject", unique: true
    t.index ["identity_provider_id"], name: "index_external_identities_on_identity_provider_id"
    t.index ["user_id"], name: "index_external_identities_on_user_id"
  end

  create_table "fedi_activities", force: :cascade do |t|
    t.string "activity_type"
    t.datetime "created_at", null: false
    t.integer "fedi_actor_id"
    t.datetime "received_at"
    t.datetime "updated_at", null: false
    t.string "uri", null: false
    t.index ["fedi_actor_id"], name: "index_fedi_activities_on_fedi_actor_id"
    t.index ["uri"], name: "index_fedi_activities_on_uri", unique: true
  end

  create_table "fedi_actors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "domain"
    t.string "followers_url"
    t.string "inbox_url", null: false
    t.datetime "last_fetched_at"
    t.text "public_key_pem"
    t.string "shared_inbox_url"
    t.datetime "updated_at", null: false
    t.string "uri", null: false
    t.string "username"
    t.index ["uri"], name: "index_fedi_actors_on_uri", unique: true
    t.index ["username", "domain"], name: "index_fedi_actors_on_username_and_domain"
  end

  create_table "fedi_follows", force: :cascade do |t|
    t.string "activity_uri"
    t.datetime "created_at", null: false
    t.integer "fedi_actor_id", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["fedi_actor_id", "user_id"], name: "index_fedi_follows_on_fedi_actor_id_and_user_id", unique: true
    t.index ["fedi_actor_id"], name: "index_fedi_follows_on_fedi_actor_id"
    t.index ["user_id", "state"], name: "index_fedi_follows_on_user_id_and_state"
    t.index ["user_id"], name: "index_fedi_follows_on_user_id"
  end

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "followed_id"
    t.integer "follower_id"
    t.datetime "updated_at", null: false
    t.index ["followed_id"], name: "index_follows_on_followed_id"
    t.index ["follower_id", "followed_id"], name: "index_follows_on_follower_id_and_followed_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
  end

  create_table "hashtags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count"
    t.index ["name"], name: "index_hashtags_on_name", unique: true
  end

  create_table "identity_assurances", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "level", null: false
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.datetime "verified_at"
    t.index ["user_id", "level"], name: "index_identity_assurances_on_user_id_and_level", unique: true
    t.index ["user_id"], name: "index_identity_assurances_on_user_id"
  end

  create_table "identity_providers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "client_id"
    t.datetime "created_at", null: false
    t.string "issuer"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_identity_providers_on_slug", unique: true
  end

  create_table "marketplace_addresses", force: :cascade do |t|
    t.string "city_name", null: false
    t.string "country_code", default: "NO", null: false
    t.datetime "created_at", null: false
    t.boolean "default_address", default: false, null: false
    t.string "line1", null: false
    t.string "line2"
    t.string "phone"
    t.string "postcode", null: false
    t.string "recipient", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "default_address"], name: "index_marketplace_addresses_on_user_id_and_default_address"
    t.index ["user_id"], name: "index_marketplace_addresses_on_user_id"
  end

  create_table "marketplace_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "parent_id"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_marketplace_categories_on_parent_id"
    t.index ["slug"], name: "index_marketplace_categories_on_slug", unique: true
  end

  create_table "marketplace_checkouts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", default: "NOK", null: false
    t.integer "marketplace_address_id"
    t.datetime "paid_at"
    t.string "payment_provider"
    t.string "payment_reference"
    t.string "status", default: "open", null: false
    t.integer "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["marketplace_address_id"], name: "index_marketplace_checkouts_on_marketplace_address_id"
    t.index ["user_id", "status"], name: "index_marketplace_checkouts_on_user_id_and_status"
    t.index ["user_id"], name: "index_marketplace_checkouts_on_user_id"
  end

  create_table "marketplace_deals", force: :cascade do |t|
    t.string "badge"
    t.datetime "created_at", null: false
    t.integer "discount_percent"
    t.datetime "ends_at"
    t.boolean "featured", default: false, null: false
    t.string "headline", null: false
    t.integer "listing_id", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "starts_at"
    t.datetime "updated_at", null: false
    t.index ["featured", "priority"], name: "index_marketplace_deals_on_featured_and_priority"
    t.index ["listing_id"], name: "index_marketplace_deals_on_listing_id"
    t.index ["starts_at", "ends_at"], name: "index_marketplace_deals_on_starts_at_and_ends_at"
  end

  create_table "marketplace_listing_favorites", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "listing_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["listing_id"], name: "index_marketplace_listing_favorites_on_listing_id"
    t.index ["user_id", "listing_id"], name: "idx_marketplace_favorites_user_listing", unique: true
    t.index ["user_id"], name: "index_marketplace_listing_favorites_on_user_id"
  end

  create_table "marketplace_listings", force: :cascade do |t|
    t.integer "category_id", null: false
    t.integer "city_id"
    t.string "condition"
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "description"
    t.datetime "expires_at"
    t.decimal "latitude", precision: 10, scale: 7
    t.string "location"
    t.decimal "longitude", precision: 10, scale: 7
    t.integer "price_cents"
    t.decimal "rating", precision: 3, scale: 2, default: "0.0", null: false
    t.datetime "renewal_notice_sent_at"
    t.integer "reviews_count", default: 0, null: false
    t.string "slug"
    t.string "status"
    t.integer "stock"
    t.integer "store_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "views_count"
    t.index ["category_id"], name: "index_marketplace_listings_on_category_id"
    t.index ["city_id", "slug"], name: "index_marketplace_listings_on_city_and_slug", unique: true
    t.index ["city_id"], name: "index_marketplace_listings_on_city_id"
    t.index ["latitude", "longitude"], name: "index_marketplace_listings_on_latitude_and_longitude"
    t.index ["status", "expires_at"], name: "index_marketplace_listings_on_status_and_expires_at"
    t.index ["store_id"], name: "index_marketplace_listings_on_store_id"
    t.index ["user_id"], name: "index_marketplace_listings_on_user_id"
  end

  create_table "marketplace_orders", force: :cascade do |t|
    t.integer "buyer_id", null: false
    t.string "carrier"
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "fulfilment_status", default: "unfulfilled", null: false
    t.string "gclid"
    t.datetime "google_conversion_uploaded_at"
    t.integer "listing_id", null: false
    t.integer "marketplace_checkout_id"
    t.text "message"
    t.datetime "paid_at"
    t.string "payment_provider"
    t.string "payment_reference"
    t.string "payment_status", default: "unpaid", null: false
    t.integer "price_cents"
    t.integer "quantity", default: 1, null: false
    t.datetime "shipped_at"
    t.string "status"
    t.string "tracking_code"
    t.datetime "updated_at", null: false
    t.index ["buyer_id"], name: "index_marketplace_orders_on_buyer_id"
    t.index ["fulfilment_status"], name: "index_marketplace_orders_on_fulfilment_status"
    t.index ["listing_id"], name: "index_marketplace_orders_on_listing_id"
    t.index ["marketplace_checkout_id"], name: "index_marketplace_orders_on_marketplace_checkout_id"
    t.index ["payment_reference"], name: "index_marketplace_orders_on_payment_reference"
    t.index ["payment_status"], name: "index_marketplace_orders_on_payment_status"
  end

  create_table "marketplace_reviews", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "listing_id", null: false
    t.integer "rating", null: false
    t.decimal "reviewer_lat", precision: 10, scale: 7
    t.decimal "reviewer_lng", precision: 10, scale: 7
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["listing_id", "created_at"], name: "index_marketplace_reviews_on_listing_id_and_created_at"
    t.index ["listing_id"], name: "index_marketplace_reviews_on_listing_id"
    t.index ["user_id", "listing_id"], name: "index_marketplace_reviews_on_user_id_and_listing_id", unique: true
    t.index ["user_id"], name: "index_marketplace_reviews_on_user_id"
  end

  create_table "marketplace_saved_searches", force: :cascade do |t|
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.datetime "last_notified_at"
    t.string "location"
    t.string "name"
    t.boolean "notify", default: false, null: false
    t.string "query"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["category_id"], name: "index_marketplace_saved_searches_on_category_id"
    t.index ["notify", "last_notified_at"], name: "idx_marketplace_saved_searches_alerting"
    t.index ["user_id"], name: "index_marketplace_saved_searches_on_user_id"
  end

  create_table "marketplace_stores", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "owner_id", null: false
    t.integer "place_id"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false, null: false
    t.string "vertical"
    t.index ["city_id"], name: "index_marketplace_stores_on_city_id"
    t.index ["owner_id"], name: "index_marketplace_stores_on_owner_id"
    t.index ["place_id"], name: "index_marketplace_stores_on_place_id"
    t.index ["slug"], name: "index_marketplace_stores_on_slug", unique: true
    t.index ["vertical", "active"], name: "index_marketplace_stores_on_vertical_and_active"
  end

  create_table "mentions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "mentionable_id", null: false
    t.string "mentionable_type", null: false
    t.integer "mentioned_user_id", null: false
    t.datetime "updated_at", null: false
    t.index ["mentionable_type", "mentionable_id"], name: "index_mentions_on_mentionable"
    t.index ["mentioned_user_id"], name: "index_mentions_on_mentioned_user_id"
  end

  create_table "message_receipts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.integer "message_id", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["message_id"], name: "index_message_receipts_on_message_id"
    t.index ["user_id"], name: "index_message_receipts_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "duration_seconds"
    t.datetime "edited_at"
    t.datetime "expires_at"
    t.string "message_type"
    t.integer "parent_id"
    t.integer "sender_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "deleted_at"], name: "index_messages_on_conversation_id_and_deleted_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["parent_id"], name: "index_messages_on_parent_id"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "moderation_flags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "flaggable_id", null: false
    t.string "flaggable_type", null: false
    t.string "kind", null: false
    t.text "reason"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["flaggable_type", "flaggable_id"], name: "index_moderation_flags_on_flaggable_type_and_flaggable_id"
    t.index ["user_id", "status"], name: "index_moderation_flags_on_user_id_and_status"
    t.index ["user_id"], name: "index_moderation_flags_on_user_id"
  end

  create_table "moderation_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details"
    t.string "reason", null: false
    t.integer "reportable_id", null: false
    t.string "reportable_type", null: false
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_moderation_reports_on_reportable_type_and_reportable_id"
    t.index ["status", "created_at"], name: "index_moderation_reports_on_status_and_created_at"
    t.index ["user_id"], name: "index_moderation_reports_on_user_id"
  end

  create_table "neighborhoods", force: :cascade do |t|
    t.integer "city_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["city_id", "slug"], name: "index_neighborhoods_on_city_id_and_slug", unique: true
    t.index ["city_id"], name: "index_neighborhoods_on_city_id"
  end

  create_table "newsletter_editions", force: :cascade do |t|
    t.string "app_name", default: "Brgen", null: false
    t.string "city"
    t.datetime "created_at", null: false
    t.string "cta_label"
    t.string "cta_url"
    t.json "deals", default: []
    t.date "edition_date", null: false
    t.string "hero_alt"
    t.string "hero_caption"
    t.string "hero_url"
    t.string "kind", null: false
    t.text "lede", null: false
    t.string "permission_line"
    t.string "preheader"
    t.datetime "sent_at"
    t.string "sign_off"
    t.json "stories", default: []
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["kind", "city", "edition_date"], name: "index_newsletter_editions_on_kind_and_city_and_edition_date", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "actor_id"
    t.text "body"
    t.datetime "created_at", null: false
    t.string "kind", default: "custom", null: false
    t.integer "notifiable_id"
    t.string "notifiable_type"
    t.datetime "read_at"
    t.integer "source_id"
    t.string "source_type"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable_type_and_notifiable_id"
    t.index ["source_type", "source_id"], name: "index_notifications_on_source_type_and_source_id"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "outbound_clicks", force: :cascade do |t|
    t.string "app", null: false
    t.datetime "created_at", null: false
    t.string "epi"
    t.boolean "guest", default: false, null: false
    t.string "merchant"
    t.bigint "subject_id"
    t.string "subject_type"
    t.string "surface"
    t.string "url_host", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_outbound_clicks_on_created_at"
    t.index ["merchant", "created_at"], name: "index_outbound_clicks_on_merchant_and_created_at"
    t.index ["subject_type", "subject_id"], name: "index_outbound_clicks_on_subject_type_and_subject_id"
  end

  create_table "partner_clicks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.integer "listing_id"
    t.integer "membership_id", null: false
    t.datetime "occurred_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.string "visitor_digest", limit: 64
    t.index ["listing_id"], name: "index_partner_clicks_on_listing_id"
    t.index ["membership_id"], name: "index_partner_clicks_on_membership_id"
    t.index ["user_id"], name: "index_partner_clicks_on_user_id"
    t.index ["visitor_digest", "expires_at"], name: "index_partner_clicks_on_visitor_digest_and_expires_at"
  end

  create_table "partner_conversions", force: :cascade do |t|
    t.datetime "approved_at"
    t.integer "click_id"
    t.integer "commission_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "NOK", null: false
    t.integer "membership_id", null: false
    t.integer "order_id", null: false
    t.integer "order_value_cents", default: 0, null: false
    t.datetime "paid_at"
    t.datetime "payable_after", null: false
    t.string "rejected_reason", limit: 200
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["click_id"], name: "index_partner_conversions_on_click_id"
    t.index ["membership_id"], name: "index_partner_conversions_on_membership_id"
    t.index ["order_id"], name: "index_partner_conversions_on_order_id", unique: true
    t.index ["status", "payable_after"], name: "index_partner_conversions_on_status_and_payable_after"
  end

  create_table "partner_memberships", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.integer "program_id", null: false
    t.string "status", default: "pending", null: false
    t.string "token", limit: 32, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["program_id", "user_id"], name: "index_partner_memberships_on_program_id_and_user_id", unique: true
    t.index ["program_id"], name: "index_partner_memberships_on_program_id"
    t.index ["token"], name: "index_partner_memberships_on_token", unique: true
    t.index ["user_id"], name: "index_partner_memberships_on_user_id"
  end

  create_table "partner_programs", force: :cascade do |t|
    t.integer "attribution_hours", default: 720, null: false
    t.boolean "auto_approve_partners", default: false, null: false
    t.integer "city_id"
    t.string "commission_model", default: "cpa_percent", null: false
    t.integer "commission_rate", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "hold_days", default: 30, null: false
    t.string "name", limit: 120, null: false
    t.string "status", default: "draft", null: false
    t.integer "store_id", null: false
    t.text "terms"
    t.datetime "updated_at", null: false
    t.index ["city_id"], name: "index_partner_programs_on_city_id"
    t.index ["status", "city_id"], name: "index_partner_programs_on_status_and_city_id"
    t.index ["store_id"], name: "index_partner_programs_on_store_id"
  end

  create_table "place_check_ins", force: :cascade do |t|
    t.datetime "checked_in_at", null: false
    t.datetime "created_at", null: false
    t.text "note"
    t.integer "place_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["place_id", "user_id", "checked_in_at"], name: "index_place_check_ins_on_place_id_and_user_id_and_checked_in_at"
    t.index ["place_id"], name: "index_place_check_ins_on_place_id"
    t.index ["user_id"], name: "index_place_check_ins_on_user_id"
  end

  create_table "places", force: :cascade do |t|
    t.string "address"
    t.integer "city_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.decimal "latitude", precision: 10, scale: 6, null: false
    t.decimal "longitude", precision: 10, scale: 6, null: false
    t.string "name", null: false
    t.integer "neighborhood_id"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["city_id", "kind"], name: "index_places_on_city_id_and_kind"
    t.index ["city_id", "slug"], name: "index_places_on_city_id_and_slug"
    t.index ["city_id"], name: "index_places_on_city_id"
    t.index ["neighborhood_id"], name: "index_places_on_neighborhood_id"
  end

  create_table "playlist_audio_versions", force: :cascade do |t|
    t.bigint "byte_size"
    t.datetime "created_at", null: false
    t.string "original_filename", limit: 255
    t.integer "track_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["track_id"], name: "index_playlist_audio_versions_on_track_id"
    t.index ["user_id"], name: "index_playlist_audio_versions_on_user_id"
  end

  create_table "playlist_collaborations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "playlist_id"
    t.string "role", default: "editor", null: false
    t.integer "set_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_id"], name: "index_playlist_collaborations_on_playlist_id"
    t.index ["set_id"], name: "index_playlist_collaborations_on_set_id"
    t.index ["user_id", "set_id", "playlist_id"], name: "idx_playlist_collab_unique", unique: true
    t.index ["user_id"], name: "index_playlist_collaborations_on_user_id"
  end

  create_table "playlist_dilla_sketches", force: :cascade do |t|
    t.integer "bars", default: 12
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "playlist_id"
    t.text "render_error"
    t.string "render_status", default: "idle", null: false
    t.datetime "rendered_at"
    t.integer "set_id"
    t.json "state", default: {}, null: false
    t.string "style", default: "dilla"
    t.integer "track_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_id", "created_at"], name: "index_playlist_dilla_sketches_on_playlist_id_and_created_at"
    t.index ["playlist_id"], name: "index_playlist_dilla_sketches_on_playlist_id"
    t.index ["set_id", "created_at"], name: "index_playlist_dilla_sketches_on_set_id_and_created_at"
    t.index ["set_id"], name: "index_playlist_dilla_sketches_on_set_id"
    t.index ["track_id"], name: "index_playlist_dilla_sketches_on_track_id"
    t.index ["user_id"], name: "index_playlist_dilla_sketches_on_user_id"
  end

  create_table "playlist_likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "playlist_id"
    t.integer "set_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_id"], name: "index_playlist_likes_on_playlist_id"
    t.index ["set_id"], name: "index_playlist_likes_on_set_id"
    t.index ["user_id", "set_id", "playlist_id"], name: "idx_playlist_likes_unique", unique: true
    t.index ["user_id"], name: "index_playlist_likes_on_user_id"
  end

  create_table "playlist_listening_parties", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_track_id"
    t.integer "host_id", null: false
    t.string "join_code", null: false
    t.integer "playlist_set_id", null: false
    t.integer "position_seconds", default: 0, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["current_track_id"], name: "index_playlist_listening_parties_on_current_track_id"
    t.index ["host_id"], name: "index_playlist_listening_parties_on_host_id"
    t.index ["join_code"], name: "index_playlist_listening_parties_on_join_code", unique: true
    t.index ["playlist_set_id", "status"], name: "index_playlist_listening_parties_on_playlist_set_id_and_status"
    t.index ["playlist_set_id"], name: "index_playlist_listening_parties_on_playlist_set_id"
  end

  create_table "playlist_listens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "playlist_track_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_track_id"], name: "index_playlist_listens_on_playlist_track_id"
    t.index ["user_id"], name: "index_playlist_listens_on_user_id"
  end

  create_table "playlist_party_messages", force: :cascade do |t|
    t.string "body", limit: 500, null: false
    t.datetime "created_at", null: false
    t.integer "listening_party_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["listening_party_id", "created_at"], name: "idx_party_messages_on_party_and_created_at"
    t.index ["listening_party_id"], name: "index_playlist_party_messages_on_listening_party_id"
    t.index ["user_id"], name: "index_playlist_party_messages_on_user_id"
  end

  create_table "playlist_playlist_tracks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "playlist_playlist_id", null: false
    t.integer "playlist_track_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_playlist_id", "playlist_track_id"], name: "idx_on_playlist_playlist_id_playlist_track_id_2abb1104d1", unique: true
    t.index ["playlist_playlist_id"], name: "index_playlist_playlist_tracks_on_playlist_playlist_id"
    t.index ["playlist_track_id"], name: "index_playlist_playlist_tracks_on_playlist_track_id"
    t.index ["user_id"], name: "index_playlist_playlist_tracks_on_user_id"
  end

  create_table "playlist_playlists", force: :cascade do |t|
    t.integer "city_id"
    t.boolean "collaborative", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "likes_count"
    t.string "name"
    t.integer "plays_count"
    t.boolean "public_access"
    t.string "slug"
    t.integer "tracks_count"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["city_id", "slug"], name: "index_playlist_playlists_on_city_and_slug", unique: true
    t.index ["city_id"], name: "index_playlist_playlists_on_city_id"
    t.index ["user_id"], name: "index_playlist_playlists_on_user_id"
  end

  create_table "playlist_set_tracks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "playlist_set_id", null: false
    t.integer "playlist_track_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_set_id", "playlist_track_id"], name: "idx_on_playlist_set_id_playlist_track_id_60911f71fd", unique: true
    t.index ["playlist_set_id"], name: "index_playlist_set_tracks_on_playlist_set_id"
    t.index ["playlist_track_id"], name: "index_playlist_set_tracks_on_playlist_track_id"
    t.index ["user_id"], name: "index_playlist_set_tracks_on_user_id"
  end

  create_table "playlist_sets", force: :cascade do |t|
    t.boolean "collaborative", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "privacy", default: "public"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_playlist_sets_on_user_id"
  end

  create_table "playlist_timestamped_comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.float "timestamp_seconds"
    t.integer "track_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["track_id", "timestamp_seconds", "created_at"], name: "index_playlist_timestamped_comments_chronological"
    t.index ["track_id"], name: "index_playlist_timestamped_comments_on_track_id"
    t.index ["user_id"], name: "index_playlist_timestamped_comments_on_user_id"
  end

  create_table "playlist_tracks", force: :cascade do |t|
    t.string "album"
    t.string "artist"
    t.datetime "audio_replaced_at"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.datetime "expires_at"
    t.string "genre"
    t.string "privacy", default: "private", null: false
    t.string "source_type"
    t.string "source_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["privacy", "expires_at"], name: "index_playlist_tracks_on_privacy_and_expires_at"
    t.index ["user_id"], name: "index_playlist_tracks_on_user_id"
  end

  create_table "posts", force: :cascade do |t|
    t.boolean "anonymous"
    t.integer "city_id"
    t.integer "comments_count", default: 0, null: false
    t.integer "community_id"
    t.text "content"
    t.datetime "created_at", null: false
    t.string "flair"
    t.integer "karma"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "removed_at"
    t.integer "reposts_count", default: 0, null: false
    t.string "slug"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["city_id", "slug"], name: "index_posts_on_city_and_slug", unique: true
    t.index ["city_id"], name: "index_posts_on_city_id"
    t.index ["community_id", "flair"], name: "index_posts_on_community_id_and_flair"
    t.index ["community_id"], name: "index_posts_on_community_id"
    t.index ["latitude", "longitude"], name: "index_posts_on_latitude_and_longitude"
    t.index ["removed_at"], name: "index_posts_on_removed_at"
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.text "endpoint", null: false
    t.string "p256dh", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "endpoint"], name: "index_push_subscriptions_on_user_id_and_endpoint", unique: true
  end

  create_table "reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "like"
    t.integer "post_id"
    t.integer "reactable_id"
    t.string "reactable_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["post_id"], name: "index_reactions_on_post_id"
    t.index ["reactable_type", "reactable_id"], name: "index_reactions_on_reactable"
    t.index ["user_id", "reactable_type", "reactable_id", "post_id", "kind"], name: "idx_reactions_unique_user_target_kind", unique: true
    t.index ["user_id"], name: "index_reactions_on_user_id"
  end

  create_table "reposts", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["post_id"], name: "index_reposts_on_post_id"
    t.index ["user_id", "post_id"], name: "index_reposts_on_user_id_and_post_id", unique: true
    t.index ["user_id"], name: "index_reposts_on_user_id"
  end

  create_table "reputation_scores", force: :cascade do |t|
    t.datetime "calculated_at"
    t.datetime "created_at", null: false
    t.string "scope", default: "global", null: false
    t.integer "score", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "scope"], name: "index_reputation_scores_on_user_id_and_scope", unique: true
    t.index ["user_id"], name: "index_reputation_scores_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stories", force: :cascade do |t|
    t.string "caption"
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "views_count", default: 0, null: false
    t.index ["city_id"], name: "index_stories_on_city_id"
    t.index ["expires_at"], name: "index_stories_on_expires_at"
    t.index ["user_id", "expires_at"], name: "index_stories_on_user_id_and_expires_at"
    t.index ["user_id"], name: "index_stories_on_user_id"
  end

  create_table "story_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "story_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["story_id", "user_id"], name: "index_story_views_on_story_id_and_user_id", unique: true
    t.index ["story_id"], name: "index_story_views_on_story_id"
    t.index ["user_id"], name: "index_story_views_on_user_id"
  end

  create_table "streams", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "duration"
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.integer "user_id", null: false
    t.index ["post_id"], name: "index_streams_on_post_id"
    t.index ["user_id"], name: "index_streams_on_user_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "hashtag_id", null: false
    t.integer "taggable_id", null: false
    t.string "taggable_type", null: false
    t.datetime "updated_at", null: false
    t.index ["hashtag_id"], name: "index_taggings_on_hashtag_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable"
  end

  create_table "takeaway_delivery_drivers", force: :cascade do |t|
    t.boolean "available", default: false, null: false
    t.datetime "created_at", null: false
    t.decimal "current_lat", precision: 10, scale: 6
    t.decimal "current_lng", precision: 10, scale: 6
    t.string "license_number"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "vehicle_type"
    t.index ["available", "current_lat", "current_lng"], name: "idx_takeaway_drivers_available_location"
    t.index ["user_id"], name: "index_takeaway_delivery_drivers_on_user_id"
  end

  create_table "takeaway_favorite_restaurants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["restaurant_id"], name: "index_takeaway_favorite_restaurants_on_restaurant_id"
    t.index ["user_id", "restaurant_id"], name: "idx_takeaway_favorites_user_restaurant", unique: true
    t.index ["user_id"], name: "index_takeaway_favorite_restaurants_on_user_id"
  end

  create_table "takeaway_menu_items", force: :cascade do |t|
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.integer "price_cents"
    t.integer "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.boolean "vegan"
    t.boolean "vegetarian"
    t.index ["restaurant_id"], name: "index_takeaway_menu_items_on_restaurant_id"
  end

  create_table "takeaway_opening_hours", force: :cascade do |t|
    t.integer "closes_minute", null: false
    t.datetime "created_at", null: false
    t.integer "opens_minute", null: false
    t.integer "restaurant_id", null: false
    t.datetime "updated_at", null: false
    t.integer "weekday", null: false
    t.index ["restaurant_id", "weekday"], name: "index_takeaway_opening_hours_on_restaurant_id_and_weekday"
    t.index ["restaurant_id"], name: "index_takeaway_opening_hours_on_restaurant_id"
  end

  create_table "takeaway_order_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "menu_item_id", null: false
    t.integer "order_id", null: false
    t.integer "quantity"
    t.integer "unit_price_cents"
    t.datetime "updated_at", null: false
    t.index ["menu_item_id"], name: "index_takeaway_order_items_on_menu_item_id"
    t.index ["order_id"], name: "index_takeaway_order_items_on_order_id"
  end

  create_table "takeaway_orders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "delivery_address"
    t.integer "delivery_driver_id"
    t.integer "delivery_fee_cents"
    t.integer "restaurant_id", null: false
    t.datetime "scheduled_for"
    t.text "special_instructions"
    t.string "status"
    t.integer "subtotal_cents"
    t.integer "tip_cents", default: 0, null: false
    t.integer "total_cents"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["delivery_driver_id", "status"], name: "index_takeaway_orders_on_delivery_driver_id_and_status"
    t.index ["delivery_driver_id"], name: "index_takeaway_orders_on_delivery_driver_id"
    t.index ["restaurant_id", "status", "updated_at"], name: "index_takeaway_orders_on_restaurant_id_and_status_and_updated_at"
    t.index ["restaurant_id"], name: "index_takeaway_orders_on_restaurant_id"
    t.index ["scheduled_for"], name: "index_takeaway_orders_on_scheduled_for"
    t.index ["user_id"], name: "index_takeaway_orders_on_user_id"
  end

  create_table "takeaway_restaurants", force: :cascade do |t|
    t.boolean "active"
    t.string "address"
    t.string "city"
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.string "cuisine_type"
    t.integer "delivery_fee_cents"
    t.text "description"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.integer "min_order_cents"
    t.string "name"
    t.string "phone"
    t.integer "place_id"
    t.decimal "rating"
    t.integer "reviews_count"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["city_id", "slug"], name: "index_takeaway_restaurants_on_city_and_slug", unique: true
    t.index ["city_id"], name: "index_takeaway_restaurants_on_city_id"
    t.index ["latitude", "longitude"], name: "index_takeaway_restaurants_on_latitude_and_longitude"
    t.index ["place_id"], name: "index_takeaway_restaurants_on_place_id"
    t.index ["user_id"], name: "index_takeaway_restaurants_on_user_id"
  end

  create_table "takeaway_reviews", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.integer "order_id", null: false
    t.integer "rating", null: false
    t.integer "restaurant_id", null: false
    t.decimal "reviewer_lat", precision: 10, scale: 7
    t.decimal "reviewer_lng", precision: 10, scale: 7
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["order_id", "user_id"], name: "index_takeaway_reviews_on_order_id_and_user_id", unique: true
    t.index ["order_id"], name: "index_takeaway_reviews_on_order_id"
    t.index ["restaurant_id", "created_at"], name: "index_takeaway_reviews_on_restaurant_id_and_created_at"
    t.index ["restaurant_id"], name: "index_takeaway_reviews_on_restaurant_id"
    t.index ["user_id"], name: "index_takeaway_reviews_on_user_id"
  end

  create_table "trust_signals", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.text "metadata"
    t.string "source"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "weight", default: 0, null: false
    t.index ["user_id", "kind"], name: "index_trust_signals_on_user_id_and_kind"
    t.index ["user_id"], name: "index_trust_signals_on_user_id"
  end

  create_table "tv_broadcasts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ended_at"
    t.datetime "started_at"
    t.string "status"
    t.string "stream_key"
    t.string "title"
    t.integer "tv_channel_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "viewer_count"
    t.index ["tv_channel_id"], name: "index_tv_broadcasts_on_tv_channel_id"
    t.index ["user_id"], name: "index_tv_broadcasts_on_user_id"
  end

  create_table "tv_channels", force: :cascade do |t|
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.string "slug"
    t.integer "subscribers_count"
    t.integer "total_views"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["city_id"], name: "index_tv_channels_on_city_id"
    t.index ["slug"], name: "index_tv_channels_on_slug", unique: true
    t.index ["user_id"], name: "index_tv_channels_on_user_id"
  end

  create_table "tv_comments", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "video_id", null: false
    t.index ["user_id"], name: "index_tv_comments_on_user_id"
    t.index ["video_id"], name: "index_tv_comments_on_video_id"
  end

  create_table "tv_episodes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "number", null: false
    t.integer "show_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "video_id"
    t.index ["show_id", "number"], name: "index_tv_episodes_on_show_id_and_number", unique: true
    t.index ["show_id"], name: "index_tv_episodes_on_show_id"
    t.index ["video_id"], name: "index_tv_episodes_on_video_id"
  end

  create_table "tv_live_streams", force: :cascade do |t|
    t.integer "channel_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "ended_at"
    t.datetime "started_at"
    t.string "status", default: "scheduled", null: false
    t.string "stream_key"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "viewer_count", default: 0, null: false
    t.index ["channel_id"], name: "index_tv_live_streams_on_channel_id"
    t.index ["status", "updated_at"], name: "index_tv_live_streams_on_status_and_updated_at"
    t.index ["stream_key"], name: "index_tv_live_streams_on_stream_key", unique: true
    t.index ["user_id"], name: "index_tv_live_streams_on_user_id"
  end

  create_table "tv_shows", force: :cascade do |t|
    t.integer "channel_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "published", default: false, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "slug"], name: "index_tv_shows_on_channel_id_and_slug", unique: true
    t.index ["channel_id"], name: "index_tv_shows_on_channel_id"
  end

  create_table "tv_stream_chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "live_stream_id", null: false
    t.text "message", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["live_stream_id", "created_at"], name: "index_tv_stream_chats_on_live_stream_id_and_created_at"
    t.index ["live_stream_id"], name: "index_tv_stream_chats_on_live_stream_id"
    t.index ["user_id"], name: "index_tv_stream_chats_on_user_id"
  end

  create_table "tv_subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "notify_on_upload"
    t.integer "tv_channel_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["tv_channel_id"], name: "index_tv_subscriptions_on_tv_channel_id"
    t.index ["user_id", "tv_channel_id"], name: "index_tv_subscriptions_on_user_id_and_tv_channel_id", unique: true
    t.index ["user_id"], name: "index_tv_subscriptions_on_user_id"
  end

  create_table "tv_video_notes", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "timestamp"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "video_id", null: false
    t.index ["user_id"], name: "index_tv_video_notes_on_user_id"
    t.index ["video_id", "timestamp", "created_at"], name: "index_tv_video_notes_on_video_id_and_timestamp_and_created_at"
    t.index ["video_id"], name: "index_tv_video_notes_on_video_id"
  end

  create_table "tv_videos", force: :cascade do |t|
    t.integer "comments_count"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.integer "likes_count"
    t.datetime "published_at"
    t.string "slug"
    t.string "status"
    t.string "thumbnail_url"
    t.string "title"
    t.integer "tv_channel_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "views_count"
    t.index ["slug"], name: "index_tv_videos_on_slug", unique: true
    t.index ["tv_channel_id"], name: "index_tv_videos_on_tv_channel_id"
    t.index ["user_id"], name: "index_tv_videos_on_user_id"
  end

  create_table "tv_view_events", force: :cascade do |t|
    t.boolean "completed"
    t.datetime "created_at", null: false
    t.integer "tv_video_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "watch_time_seconds"
    t.index ["tv_video_id"], name: "index_tv_view_events_on_tv_video_id"
    t.index ["user_id"], name: "index_tv_view_events_on_user_id"
  end

  create_table "typing_indicators", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["conversation_id"], name: "index_typing_indicators_on_conversation_id"
    t.index ["user_id"], name: "index_typing_indicators_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "bot", default: false, null: false
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.datetime "deletion_scheduled_at"
    t.string "display_name"
    t.string "email_address", null: false
    t.string "email_verification_token"
    t.datetime "email_verified_at"
    t.boolean "guest", default: false, null: false
    t.integer "karma"
    t.decimal "latitude", precision: 10, scale: 7
    t.datetime "location_updated_at"
    t.decimal "longitude", precision: 10, scale: 7
    t.datetime "magic_link_expires_at"
    t.string "magic_link_token"
    t.string "otp_secret"
    t.string "password_digest", null: false
    t.text "persona"
    t.text "private_key"
    t.text "public_key"
    t.string "remember_token"
    t.datetime "remember_token_expires_at"
    t.boolean "two_factor_enabled", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["city_id"], name: "index_users_on_city_id"
    t.index ["deletion_scheduled_at"], name: "index_users_on_deletion_scheduled_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["email_verification_token"], name: "index_users_on_email_verification_token", unique: true
    t.index ["guest", "created_at"], name: "index_users_on_guest_and_created_at"
    t.index ["magic_link_token"], name: "index_users_on_magic_link_token", unique: true
    t.index ["remember_token"], name: "index_users_on_remember_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "value"
    t.integer "votable_id", null: false
    t.string "votable_type", null: false
    t.index ["user_id", "votable_type", "votable_id"], name: "index_votes_on_user_id_and_votable_type_and_votable_id", unique: true
    t.index ["user_id"], name: "index_votes_on_user_id"
    t.index ["votable_type", "votable_id"], name: "index_votes_on_votable"
  end

  add_foreign_key "account_merges", "users"
  add_foreign_key "account_merges", "users", column: "guest_user_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activity_events", "users", column: "actor_id"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "blocks", "users", column: "blocked_id"
  add_foreign_key "blocks", "users", column: "blocker_id"
  add_foreign_key "bookmarks", "posts"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "comments", "users"
  add_foreign_key "communities", "cities"
  add_foreign_key "community_bans", "communities"
  add_foreign_key "community_bans", "users"
  add_foreign_key "community_bans", "users", column: "banned_by_id"
  add_foreign_key "community_memberships", "communities"
  add_foreign_key "community_memberships", "users"
  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversation_participants", "users"
  add_foreign_key "dating_dislikes", "users", column: "dislikee_id"
  add_foreign_key "dating_dislikes", "users", column: "disliker_id"
  add_foreign_key "dating_likes", "dating_prompts"
  add_foreign_key "dating_likes", "users", column: "likee_id"
  add_foreign_key "dating_likes", "users", column: "liker_id"
  add_foreign_key "dating_matches", "users", column: "initiator_id"
  add_foreign_key "dating_matches", "users", column: "receiver_id"
  add_foreign_key "dating_profiles", "cities"
  add_foreign_key "dating_profiles", "users"
  add_foreign_key "dating_prompts", "dating_profiles", column: "profile_id"
  add_foreign_key "event_rsvps", "events"
  add_foreign_key "event_rsvps", "users"
  add_foreign_key "events", "cities"
  add_foreign_key "events", "neighborhoods"
  add_foreign_key "events", "places"
  add_foreign_key "events", "users"
  add_foreign_key "external_identities", "identity_providers"
  add_foreign_key "external_identities", "users"
  add_foreign_key "fedi_activities", "fedi_actors"
  add_foreign_key "fedi_follows", "fedi_actors"
  add_foreign_key "fedi_follows", "users"
  add_foreign_key "identity_assurances", "users"
  add_foreign_key "marketplace_addresses", "users"
  add_foreign_key "marketplace_checkouts", "marketplace_addresses"
  add_foreign_key "marketplace_checkouts", "users"
  add_foreign_key "marketplace_deals", "marketplace_listings", column: "listing_id"
  add_foreign_key "marketplace_listing_favorites", "marketplace_listings", column: "listing_id"
  add_foreign_key "marketplace_listing_favorites", "users"
  add_foreign_key "marketplace_listings", "cities"
  add_foreign_key "marketplace_listings", "marketplace_categories", column: "category_id"
  add_foreign_key "marketplace_listings", "marketplace_stores", column: "store_id"
  add_foreign_key "marketplace_listings", "users"
  add_foreign_key "marketplace_orders", "marketplace_checkouts"
  add_foreign_key "marketplace_orders", "marketplace_listings", column: "listing_id"
  add_foreign_key "marketplace_orders", "users", column: "buyer_id"
  add_foreign_key "marketplace_reviews", "marketplace_listings", column: "listing_id"
  add_foreign_key "marketplace_reviews", "users"
  add_foreign_key "marketplace_saved_searches", "users"
  add_foreign_key "marketplace_stores", "cities"
  add_foreign_key "marketplace_stores", "places"
  add_foreign_key "marketplace_stores", "users", column: "owner_id"
  add_foreign_key "mentions", "users", column: "mentioned_user_id"
  add_foreign_key "message_receipts", "messages"
  add_foreign_key "message_receipts", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "messages", column: "parent_id"
  add_foreign_key "moderation_flags", "users"
  add_foreign_key "moderation_reports", "users"
  add_foreign_key "neighborhoods", "cities"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "partner_clicks", "marketplace_listings", column: "listing_id"
  add_foreign_key "partner_clicks", "partner_memberships", column: "membership_id"
  add_foreign_key "partner_clicks", "users"
  add_foreign_key "partner_conversions", "marketplace_orders", column: "order_id"
  add_foreign_key "partner_conversions", "partner_clicks", column: "click_id"
  add_foreign_key "partner_conversions", "partner_memberships", column: "membership_id"
  add_foreign_key "partner_memberships", "partner_programs", column: "program_id"
  add_foreign_key "partner_memberships", "users"
  add_foreign_key "partner_programs", "cities"
  add_foreign_key "partner_programs", "marketplace_stores", column: "store_id"
  add_foreign_key "place_check_ins", "places"
  add_foreign_key "place_check_ins", "users"
  add_foreign_key "places", "cities"
  add_foreign_key "places", "neighborhoods"
  add_foreign_key "playlist_audio_versions", "playlist_tracks", column: "track_id"
  add_foreign_key "playlist_audio_versions", "users"
  add_foreign_key "playlist_collaborations", "playlist_sets", column: "set_id"
  add_foreign_key "playlist_collaborations", "users"
  add_foreign_key "playlist_dilla_sketches", "playlist_playlists", column: "playlist_id"
  add_foreign_key "playlist_dilla_sketches", "playlist_sets", column: "set_id"
  add_foreign_key "playlist_dilla_sketches", "playlist_tracks", column: "track_id"
  add_foreign_key "playlist_dilla_sketches", "users"
  add_foreign_key "playlist_likes", "playlist_sets", column: "set_id"
  add_foreign_key "playlist_likes", "users"
  add_foreign_key "playlist_listening_parties", "playlist_sets"
  add_foreign_key "playlist_listening_parties", "playlist_tracks", column: "current_track_id"
  add_foreign_key "playlist_listening_parties", "users", column: "host_id"
  add_foreign_key "playlist_listens", "playlist_tracks"
  add_foreign_key "playlist_listens", "users"
  add_foreign_key "playlist_party_messages", "playlist_listening_parties", column: "listening_party_id"
  add_foreign_key "playlist_party_messages", "users"
  add_foreign_key "playlist_playlist_tracks", "playlist_playlists"
  add_foreign_key "playlist_playlist_tracks", "playlist_tracks"
  add_foreign_key "playlist_playlist_tracks", "users"
  add_foreign_key "playlist_playlists", "cities"
  add_foreign_key "playlist_playlists", "users"
  add_foreign_key "playlist_set_tracks", "playlist_sets"
  add_foreign_key "playlist_set_tracks", "playlist_tracks"
  add_foreign_key "playlist_set_tracks", "users"
  add_foreign_key "playlist_sets", "users"
  add_foreign_key "playlist_timestamped_comments", "playlist_tracks", column: "track_id"
  add_foreign_key "playlist_timestamped_comments", "users"
  add_foreign_key "playlist_tracks", "users"
  add_foreign_key "posts", "cities"
  add_foreign_key "posts", "communities"
  add_foreign_key "posts", "users"
  add_foreign_key "reactions", "posts"
  add_foreign_key "reactions", "users"
  add_foreign_key "reposts", "posts"
  add_foreign_key "reposts", "users"
  add_foreign_key "reputation_scores", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "stories", "cities"
  add_foreign_key "stories", "users"
  add_foreign_key "story_views", "stories"
  add_foreign_key "story_views", "users"
  add_foreign_key "streams", "posts"
  add_foreign_key "streams", "users"
  add_foreign_key "taggings", "hashtags"
  add_foreign_key "takeaway_delivery_drivers", "users"
  add_foreign_key "takeaway_favorite_restaurants", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_favorite_restaurants", "users"
  add_foreign_key "takeaway_menu_items", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_opening_hours", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_order_items", "takeaway_menu_items", column: "menu_item_id"
  add_foreign_key "takeaway_order_items", "takeaway_orders", column: "order_id"
  add_foreign_key "takeaway_orders", "takeaway_delivery_drivers", column: "delivery_driver_id"
  add_foreign_key "takeaway_orders", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_orders", "users"
  add_foreign_key "takeaway_restaurants", "cities"
  add_foreign_key "takeaway_restaurants", "places"
  add_foreign_key "takeaway_restaurants", "users"
  add_foreign_key "takeaway_reviews", "takeaway_orders", column: "order_id"
  add_foreign_key "takeaway_reviews", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_reviews", "users"
  add_foreign_key "trust_signals", "users"
  add_foreign_key "tv_broadcasts", "tv_channels"
  add_foreign_key "tv_broadcasts", "users"
  add_foreign_key "tv_channels", "cities"
  add_foreign_key "tv_channels", "users"
  add_foreign_key "tv_comments", "tv_videos", column: "video_id"
  add_foreign_key "tv_comments", "users"
  add_foreign_key "tv_episodes", "tv_shows", column: "show_id"
  add_foreign_key "tv_episodes", "tv_videos", column: "video_id"
  add_foreign_key "tv_live_streams", "tv_channels", column: "channel_id"
  add_foreign_key "tv_live_streams", "users"
  add_foreign_key "tv_shows", "tv_channels", column: "channel_id"
  add_foreign_key "tv_stream_chats", "tv_live_streams", column: "live_stream_id"
  add_foreign_key "tv_stream_chats", "users"
  add_foreign_key "tv_subscriptions", "tv_channels"
  add_foreign_key "tv_subscriptions", "users"
  add_foreign_key "tv_video_notes", "tv_videos", column: "video_id"
  add_foreign_key "tv_video_notes", "users"
  add_foreign_key "tv_videos", "tv_channels"
  add_foreign_key "tv_videos", "users"
  add_foreign_key "tv_view_events", "tv_videos"
  add_foreign_key "tv_view_events", "users"
  add_foreign_key "typing_indicators", "conversations"
  add_foreign_key "typing_indicators", "users"
  add_foreign_key "users", "cities"
  add_foreign_key "votes", "users"
end
