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

ActiveRecord::Schema[8.1].define(version: 2026_05_17_144635) do

  create_table "push_subscriptions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.text "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "endpoint"], name: "index_push_subscriptions_on_user_id_and_endpoint", unique: true
  end
  create_table "comments", force: :cascade do |t|
    t.integer "commentable_id", null: false
    t.string "commentable_type", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["commentable_type", "commentable_id"], name: "index_comments_on_commentable"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "communities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.string "slug"
    t.string "subdomain"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["slug"], name: "index_communities_on_slug", unique: true
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
    t.datetime "created_at", null: false
    t.string "gender"
    t.decimal "latitude"
    t.string "location"
    t.decimal "longitude"
    t.string "looking_for"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.boolean "visible"
    t.index ["user_id"], name: "index_dating_profiles_on_user_id"
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

  create_table "marketplace_listings", force: :cascade do |t|
    t.integer "category_id", null: false
    t.string "condition"
    t.datetime "created_at", null: false
    t.string "currency"
    t.text "description"
    t.string "location"
    t.integer "price_cents"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "views_count"
    t.index ["category_id"], name: "index_marketplace_listings_on_category_id"
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
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "likes_count"
    t.string "name"
    t.integer "plays_count"
    t.boolean "public_access"
    t.integer "tracks_count"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_playlist_playlists_on_user_id"
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
    t.integer "community_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "karma"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["community_id"], name: "index_posts_on_community_id"
    t.index ["user_id"], name: "index_posts_on_user_id"
  end

  create_table "reactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind"
    t.integer "post_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["post_id"], name: "index_reactions_on_post_id"
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
    t.integer "delivery_fee_cents"
    t.integer "restaurant_id", null: false
    t.text "special_instructions"
    t.string "status"
    t.integer "subtotal_cents"
    t.integer "total_cents"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["restaurant_id"], name: "index_takeaway_orders_on_restaurant_id"
    t.index ["user_id"], name: "index_takeaway_orders_on_user_id"
  end

  create_table "takeaway_restaurants", force: :cascade do |t|
    t.boolean "active"
    t.string "address"
    t.string "city"
    t.datetime "created_at", null: false
    t.string "cuisine_type"
    t.integer "delivery_fee_cents"
    t.text "description"
    t.integer "min_order_cents"
    t.string "name"
    t.string "phone"
    t.decimal "rating"
    t.integer "reviews_count"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_takeaway_restaurants_on_user_id"
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
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.string "slug"
    t.integer "subscribers_count"
    t.integer "total_views"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_tv_channels_on_user_id"
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
    t.datetime "created_at", null: false
    t.string "display_name"
    t.string "email_address", null: false
    t.boolean "guest", default: false, null: false
    t.integer "karma"
    t.decimal "latitude",  precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.datetime "location_updated_at"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username"
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

  add_foreign_key "comments", "users"
  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversation_participants", "users"
  add_foreign_key "dating_dislikes", "dislikees"
  add_foreign_key "dating_dislikes", "dislikers"
  add_foreign_key "dating_likes", "likees"
  add_foreign_key "dating_likes", "likers"
  add_foreign_key "dating_matches", "initiators"
  add_foreign_key "dating_matches", "receivers"
  add_foreign_key "dating_profiles", "users"
  add_foreign_key "marketplace_listings", "categories"
  add_foreign_key "marketplace_listings", "users"
  add_foreign_key "marketplace_orders", "buyers"
  add_foreign_key "marketplace_orders", "listings"
  add_foreign_key "mentions", "users", column: "mentioned_user_id"
  add_foreign_key "message_receipts", "messages"
  add_foreign_key "message_receipts", "users"
  add_foreign_key "messages", "conversations"
  add_foreign_key "playlist_listens", "playlist_tracks"
  add_foreign_key "playlist_listens", "users"
  add_foreign_key "playlist_playlist_tracks", "playlist_playlists"
  add_foreign_key "playlist_playlist_tracks", "playlist_tracks"
  add_foreign_key "playlist_playlist_tracks", "users"
  add_foreign_key "playlist_playlists", "users"
  add_foreign_key "posts", "communities"
  add_foreign_key "posts", "users"
  add_foreign_key "reactions", "posts"
  add_foreign_key "reactions", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "streams", "posts"
  add_foreign_key "streams", "users"
  add_foreign_key "taggings", "hashtags"
  add_foreign_key "takeaway_menu_items", "restaurants"
  add_foreign_key "takeaway_order_items", "menu_items"
  add_foreign_key "takeaway_order_items", "orders"
  add_foreign_key "takeaway_orders", "restaurants"
  add_foreign_key "takeaway_orders", "users"
  add_foreign_key "takeaway_restaurants", "users"
  add_foreign_key "tv_broadcasts", "tv_channels"
  add_foreign_key "tv_broadcasts", "users"
  add_foreign_key "tv_channels", "users"
  add_foreign_key "tv_subscriptions", "tv_channels"
  add_foreign_key "tv_subscriptions", "users"
  add_foreign_key "tv_videos", "tv_channels"
  add_foreign_key "tv_videos", "users"
  add_foreign_key "tv_view_events", "tv_videos"
  add_foreign_key "tv_view_events", "users"
  add_foreign_key "typing_indicators", "conversations"
  add_foreign_key "typing_indicators", "users"
  add_foreign_key "votes", "users"
end
