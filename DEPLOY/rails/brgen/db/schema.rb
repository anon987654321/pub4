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

ActiveRecord::Schema[8.1].define(version: 2026_06_25_120000) do
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
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.datetime "summary_updated_at"
    t.text "thread_summary"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "communities", force: :cascade do |t|
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.string "slug"
    t.string "subdomain"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["city_id", "slug"], name: "index_communities_on_city_id_and_slug", unique: true
    t.index ["city_id"], name: "index_communities_on_city_id"
    t.index ["subdomain"], name: "index_communities_on_subdomain", unique: true
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "conversation_type"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "dating_dislikes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "dislikee_id", null: false
    t.integer "disliker_id", null: false
    t.datetime "updated_at", null: false
    t.index ["dislikee_id"], name: "index_dating_dislikes_on_dislikee_id"
    t.index ["disliker_id"], name: "index_dating_dislikes_on_disliker_id"
  end

  create_table "dating_likes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "likee_id", null: false
    t.integer "liker_id", null: false
    t.datetime "updated_at", null: false
    t.index ["likee_id"], name: "index_dating_likes_on_likee_id"
    t.index ["liker_id"], name: "index_dating_likes_on_liker_id"
  end

  create_table "dating_matches", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "initiator_id", null: false
    t.integer "receiver_id", null: false
    t.string "status"
    t.datetime "updated_at", null: false
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

  create_table "follows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "followed_id"
    t.integer "follower_id"
    t.datetime "updated_at", null: false
    t.index ["followed_id"], name: "index_follows_on_followed_id"
    t.index ["follower_id"], name: "index_follows_on_follower_id"
  end

  create_table "hashtags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.integer "usage_count"
    t.index ["name"], name: "index_hashtags_on_name", unique: true
  end

  create_table "marketplace_categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "parent_id"
    t.string "slug"
    t.datetime "updated_at", null: false
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
    t.string "location"
    t.integer "price_cents"
    t.string "status"
    t.integer "store_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "views_count"
    t.index ["category_id"], name: "index_marketplace_listings_on_category_id"
    t.index ["city_id"], name: "index_marketplace_listings_on_city_id"
    t.index ["store_id"], name: "index_marketplace_listings_on_store_id"
    t.index ["user_id"], name: "index_marketplace_listings_on_user_id"
  end

  create_table "marketplace_orders", force: :cascade do |t|
    t.integer "buyer_id", null: false
    t.datetime "created_at", null: false
    t.integer "listing_id", null: false
    t.text "message"
    t.integer "price_cents"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["buyer_id"], name: "index_marketplace_orders_on_buyer_id"
    t.index ["listing_id"], name: "index_marketplace_orders_on_listing_id"
  end

  create_table "marketplace_saved_searches", force: :cascade do |t|
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.string "location"
    t.string "name"
    t.boolean "notify", default: false, null: false
    t.string "query"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_marketplace_saved_searches_on_user_id"
  end

  create_table "marketplace_stores", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "owner_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false, null: false
    t.string "vertical"
    t.index ["city_id"], name: "index_marketplace_stores_on_city_id"
    t.index ["owner_id"], name: "index_marketplace_stores_on_owner_id"
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
    t.text "content"
    t.integer "conversation_id", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "message_type"
    t.integer "sender_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
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
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "playlist_id"
    t.integer "set_id"
    t.json "state", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_id", "created_at"], name: "index_playlist_dilla_sketches_on_playlist_id_and_created_at"
    t.index ["playlist_id"], name: "index_playlist_dilla_sketches_on_playlist_id"
    t.index ["set_id", "created_at"], name: "index_playlist_dilla_sketches_on_set_id_and_created_at"
    t.index ["set_id"], name: "index_playlist_dilla_sketches_on_set_id"
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

  create_table "playlist_listens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "playlist_track_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["playlist_track_id"], name: "index_playlist_listens_on_playlist_track_id"
    t.index ["user_id"], name: "index_playlist_listens_on_user_id"
  end

  create_table "playlist_playlist_tracks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "playlist_playlist_id", null: false
    t.integer "playlist_track_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
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
    t.integer "tracks_count"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
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

  create_table "playlist_tracks", force: :cascade do |t|
    t.string "album"
    t.string "artist"
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "genre"
    t.string "source_type"
    t.string "source_url"
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "posts", force: :cascade do |t|
    t.boolean "anonymous"
    t.integer "city_id"
    t.integer "community_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "karma"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["city_id"], name: "index_posts_on_city_id"
    t.index ["community_id"], name: "index_posts_on_community_id"
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

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
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
    t.boolean "available"
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
    t.text "special_instructions"
    t.string "status"
    t.integer "subtotal_cents"
    t.integer "total_cents"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["delivery_driver_id", "status"], name: "index_takeaway_orders_on_delivery_driver_id_and_status"
    t.index ["delivery_driver_id"], name: "index_takeaway_orders_on_delivery_driver_id"
    t.index ["restaurant_id"], name: "index_takeaway_orders_on_restaurant_id"
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
    t.decimal "rating"
    t.integer "reviews_count"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["city_id"], name: "index_takeaway_restaurants_on_city_id"
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
    t.index ["order_id"], name: "index_takeaway_reviews_on_order_id"
    t.index ["restaurant_id", "created_at"], name: "index_takeaway_reviews_on_restaurant_id_and_created_at"
    t.index ["restaurant_id"], name: "index_takeaway_reviews_on_restaurant_id"
    t.index ["user_id"], name: "index_takeaway_reviews_on_user_id"
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
    t.string "status"
    t.string "thumbnail_url"
    t.string "title"
    t.integer "tv_channel_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "views_count"
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
    t.integer "city_id"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.boolean "guest", default: false, null: false
    t.integer "karma"
    t.decimal "latitude", precision: 10, scale: 7
    t.datetime "location_updated_at"
    t.decimal "longitude", precision: 10, scale: 7
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["city_id"], name: "index_users_on_city_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "value"
    t.integer "votable_id", null: false
    t.string "votable_type", null: false
    t.index ["user_id"], name: "index_votes_on_user_id"
    t.index ["votable_type", "votable_id"], name: "index_votes_on_votable"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "activity_events", "users", column: "actor_id"
  add_foreign_key "comments", "users"
  add_foreign_key "communities", "cities"
  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversation_participants", "users"
  add_foreign_key "dating_dislikes", "users", column: "dislikee_id"
  add_foreign_key "dating_dislikes", "users", column: "disliker_id"
  add_foreign_key "dating_likes", "users", column: "likee_id"
  add_foreign_key "dating_likes", "users", column: "liker_id"
  add_foreign_key "dating_matches", "users", column: "initiator_id"
  add_foreign_key "dating_matches", "users", column: "receiver_id"
  add_foreign_key "dating_profiles", "cities"
  add_foreign_key "dating_profiles", "users"
  add_foreign_key "marketplace_deals", "marketplace_listings", column: "listing_id"
  add_foreign_key "marketplace_listing_favorites", "marketplace_listings", column: "listing_id"
  add_foreign_key "marketplace_listing_favorites", "users"
  add_foreign_key "marketplace_listings", "cities"
  add_foreign_key "marketplace_listings", "marketplace_categories", column: "category_id"
  add_foreign_key "marketplace_listings", "marketplace_stores", column: "store_id"
  add_foreign_key "marketplace_listings", "users"
  add_foreign_key "marketplace_orders", "marketplace_listings", column: "listing_id"
  add_foreign_key "marketplace_orders", "users", column: "buyer_id"
  add_foreign_key "marketplace_saved_searches", "users"
  add_foreign_key "marketplace_stores", "cities"
  add_foreign_key "marketplace_stores", "users", column: "owner_id"
  add_foreign_key "mentions", "users", column: "mentioned_user_id"
  add_foreign_key "message_receipts", "messages"
  add_foreign_key "message_receipts", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "moderation_reports", "users"
  add_foreign_key "neighborhoods", "cities"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "places", "cities"
  add_foreign_key "places", "neighborhoods"
  add_foreign_key "playlist_collaborations", "playlist_sets", column: "set_id"
  add_foreign_key "playlist_collaborations", "users"
  add_foreign_key "playlist_dilla_sketches", "playlist_playlists", column: "playlist_id"
  add_foreign_key "playlist_dilla_sketches", "playlist_sets", column: "set_id"
  add_foreign_key "playlist_dilla_sketches", "users"
  add_foreign_key "playlist_likes", "playlist_sets", column: "set_id"
  add_foreign_key "playlist_likes", "users"
  add_foreign_key "playlist_listens", "playlist_tracks"
  add_foreign_key "playlist_listens", "users"
  add_foreign_key "playlist_playlist_tracks", "playlist_playlists"
  add_foreign_key "playlist_playlist_tracks", "playlist_tracks"
  add_foreign_key "playlist_playlist_tracks", "users"
  add_foreign_key "playlist_playlists", "cities"
  add_foreign_key "playlist_playlists", "users"
  add_foreign_key "playlist_set_tracks", "playlist_sets"
  add_foreign_key "playlist_set_tracks", "playlist_tracks"
  add_foreign_key "playlist_set_tracks", "users"
  add_foreign_key "playlist_sets", "users"
  add_foreign_key "posts", "cities"
  add_foreign_key "posts", "communities"
  add_foreign_key "posts", "users"
  add_foreign_key "reactions", "posts"
  add_foreign_key "reactions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "streams", "posts"
  add_foreign_key "streams", "users"
  add_foreign_key "taggings", "hashtags"
  add_foreign_key "takeaway_delivery_drivers", "users"
  add_foreign_key "takeaway_favorite_restaurants", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_favorite_restaurants", "users"
  add_foreign_key "takeaway_menu_items", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_order_items", "takeaway_menu_items", column: "menu_item_id"
  add_foreign_key "takeaway_order_items", "takeaway_orders", column: "order_id"
  add_foreign_key "takeaway_orders", "takeaway_delivery_drivers", column: "delivery_driver_id"
  add_foreign_key "takeaway_orders", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_orders", "users"
  add_foreign_key "takeaway_restaurants", "cities"
  add_foreign_key "takeaway_restaurants", "users"
  add_foreign_key "takeaway_reviews", "takeaway_orders", column: "order_id"
  add_foreign_key "takeaway_reviews", "takeaway_restaurants", column: "restaurant_id"
  add_foreign_key "takeaway_reviews", "users"
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
