# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../shared/app/services/shared/cache_policy'
require_relative '../../../shared/app/services/shared/cache_health'
require_relative '../../../shared/app/services/shared/cable_health'
require_relative '../../../shared/app/services/shared/queue_failure_summary'

class DeployBacklogTest < Minitest::Test
  ROOT = ENV.fetch('PUB4_RAILS_ROOT') do
    app = ENV.fetch('PUB4_CI_APP', 'brgen')
    candidates = [
      # Canonical checkout first: per-app "pub4-rails" copies are leftovers from
      # older deploy schemes and can go stale relative to the real monorepo
      # without anything noticing (confirmed 2026-07-10: a stale
      # /home/<app>/pub4-rails/RAILS caused every DeployBacklogTest assertion to
      # silently check month-old file contents instead of failing loudly).
      '/home/dev/pub4/RAILS',
      "/home/#{app}/pub4-rails/RAILS",
      File.expand_path('../../..', __dir__)
    ]
    candidates.find { |path| File.readable?(File.join(path, 'shared', 'app')) } ||
      candidates.find { |path| File.directory?(File.join(path, 'shared')) } ||
      candidates.last
  end.freeze

  def test_shared_cache_policy_exposes_explicit_ttls
    assert_equal 300, Shared::CachePolicy.ttl_for(:feed_fragment)
    assert_equal 3600, Shared::CachePolicy.ttl_for(:user_profile)
    assert_equal 900, Shared::CachePolicy.ttl_for(:search_results)
    assert_equal 86_400, Shared::CachePolicy.ttl_for(:static_page)
  end

  def test_admin_jobs_route_is_mounted_in_app_routes
    %w[
      amber/config/routes.rb
      brgen/config/routes.rb
      bsdports/config/routes.rb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'mount SolidQueue::Engine, at: "/admin/jobs"'
      assert_match(/jobs_constraint = lambda \{ \|request\|/, source)
      assert_includes source, "cookie_jar.signed[:session_id]"
      assert_includes source, "Session.exists?"
    end
  end

  def test_cache_health_alert_trips_above_eighty_percent
    assert Shared::CacheHealth.alert?(bytes_used: 81, max_size_bytes: 100)
    refute Shared::CacheHealth.alert?(bytes_used: 79, max_size_bytes: 100)
    assert_equal 81.0, Shared::CacheHealth.usage_percent(bytes_used: 81, max_size_bytes: 100)
    assert_match(/brgen cache at 81.0%/, Shared::CacheHealth.message(app: 'brgen', bytes_used: 81, max_size_bytes: 100))
  end

  def test_cache_health_job_is_scheduled
    source = File.read(File.join(ROOT, 'brgen/config/recurring.yml'))
    assert_includes source, 'cache_health_check:'
    assert_includes source, 'class: CacheHealthJob'
    assert_includes source, 'schedule: every day at 4am'
  end

  def test_omniauth_wires_installed_providers_to_identity_primitives
    initializer = File.read(File.join(ROOT, 'shared/config/initializers/omniauth.rb'))
    callback = File.read(File.join(ROOT, 'shared/app/controllers/omniauth_callbacks_controller.rb'))
    links = File.read(File.join(ROOT, 'shared/app/views/shared/_oauth_links.html.erb'))

    assert_includes initializer, ':google_oauth2'
    assert_includes initializer, ':github'
    assert_includes initializer, ':vipps'
    assert_includes initializer, ':snapchat'
    assert_includes initializer, 'oauth_provider_slugs'
    assert_includes callback, 'persist_external_identity'
    assert_includes callback, 'IdentityProvider.find_or_create_by!'
    assert_includes callback, 'ExternalIdentity.table_exists?'
    assert_includes callback, 'Shared::Authentication.table_exists?'
    assert_includes links, 'oauth_provider_slugs'
    assert_includes links, '/auth/google_oauth2'
    assert_includes links, '/auth/snapchat'
  end

  def test_nearby_geolocation_uses_explicit_radius_and_exact_distance
    nearby = File.read(File.join(ROOT, 'brgen/app/controllers/nearby_controller.rb'))
    locations = File.read(File.join(ROOT, 'brgen/app/controllers/locations_controller.rb'))
    geolocation = File.read(File.join(ROOT, 'brgen/app/javascript/controllers/geolocation_controller.js'))
    layout = File.read(File.join(ROOT, 'brgen/app/views/layouts/application.html.erb'))
    nearby_view = File.read(File.join(ROOT, 'brgen/app/views/nearby/index.html.erb'))
    dating_matchmaking = File.read(File.join(ROOT, 'brgen/app/services/dating/matchmaking_service.rb'))

    assert_includes nearby, 'DEFAULT_RADIUS_KM = 2.0'
    assert_includes nearby, 'MAX_RADIUS_KM = 25.0'
    assert_includes nearby, 'value.to_f.clamp(0.5, MAX_RADIUS_KM)'
    assert_includes nearby, 'distance > radius'
    assert_includes locations, 'ALERT_RADIUS_KM = NearbyController::DEFAULT_RADIUS_KM'
    assert_includes locations, 'other.distance_to(lat, lng).to_f > ALERT_RADIUS_KM'
    assert_includes geolocation, 'radiusKm'
    assert_includes geolocation, 'credentials: "same-origin"'
    assert_includes layout, 'data-geolocation-radius-km-value="2"'
    assert_includes nearby_view, 'number_with_precision(distance, precision: 1)'
    assert_includes dating_matchmaking, 'radius_km: DEFAULT_RADIUS_KM'
  end

  def test_moderation_reports_create_flags_and_reputation_effects
    workflow = File.read(File.join(ROOT, 'brgen/app/services/moderation_workflow.rb'))
    reports = File.read(File.join(ROOT, 'brgen/app/controllers/reports_controller.rb'))
    admin = File.read(File.join(ROOT, 'brgen/app/controllers/admin/reports_controller.rb'))

    assert_includes reports, 'ModerationWorkflow.report!'
    assert_includes admin, 'ModerationWorkflow.transition!'
    assert_includes workflow, 'ModerationReport.create!'
    assert_includes workflow, 'ModerationFlag.where'
    assert_includes workflow, 'flag.save!'
    assert_includes workflow, 'update_all(status: status'
    assert_includes workflow, 'kind: "spam_report"'
    assert_includes workflow, 'TrustScoreCalculator.new(user: user).call'
    assert_includes workflow, 'accountable_user'
  end

  def test_media_pipeline_processes_image_variants_across_upload_surfaces
    concern = File.read(File.join(ROOT, 'shared/app/models/concerns/shared/media_processable.rb'))
    job = File.read(File.join(ROOT, 'shared/app/jobs/shared/media_processing_job.rb'))

    assert_includes concern, 'process_media_variants'
    assert_includes concern, 'after_commit :enqueue_media_variant_processing'
    assert_includes concern, 'Shared::MediaProcessingJob.perform_later'
    assert_includes job, 'file.content_type.to_s.start_with?("image/")'

    %w[
      brgen/app/models/post.rb
      brgen/app/models/marketplace/listing.rb
      brgen/app/models/dating/profile.rb
      brgen/app/models/message.rb
      brgen/app/models/playlist/track.rb
      brgen/app/models/takeaway/menu_item.rb
      brgen/app/models/tv/broadcast.rb
      brgen/app/models/tv/channel.rb
      brgen/app/models/tv/video.rb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'include Shared::MediaProcessable'
      assert_includes source, 'process_media_variants'
      assert_includes source, 'format: :webp'
    end

    helper_source = File.read(File.join(ROOT, 'brgen/app/helpers/application_helper.rb'))
    assert_includes helper_source, 'responsive_image_tag'
    assert_includes helper_source, 'lazy_image_blurhash_value'
  end

  def test_activity_graph_emits_across_vertical_models
    concern = File.read(File.join(ROOT, 'shared/app/models/concerns/shared/activity_trackable.rb'))
    assert_includes concern, 'Shared::DomainEvent.record!'
    assert_includes concern, 'legacy_event_name'

    expected_events = {
      'brgen/app/models/playlist/playlist.rb' => %w[PlaylistCreated playlist],
      'brgen/app/models/playlist/set.rb' => %w[PlaylistSetCreated playlist],
      'brgen/app/models/playlist/track.rb' => %w[PlaylistTrackCreated playlist],
      'brgen/app/models/playlist/listen.rb' => %w[PlaylistListen playlist],
      'brgen/app/models/playlist/like.rb' => %w[PlaylistLiked playlist],
      'brgen/app/models/playlist/collaboration.rb' => %w[PlaylistCollaborationCreated playlist],
      'brgen/app/models/playlist/dilla_sketch.rb' => %w[DillaSketchCreated playlist],
      'brgen/app/models/marketplace/store.rb' => %w[MarketplaceStoreCreated marketplace],
      'brgen/app/models/marketplace/listing.rb' => %w[ListingCreated marketplace],
      'brgen/app/models/marketplace/deal.rb' => %w[MarketplaceDealCreated marketplace],
      'brgen/app/models/marketplace/listing_favorite.rb' => %w[MarketplaceListingFavorited marketplace],
      'brgen/app/models/takeaway/restaurant.rb' => %w[TakeawayRestaurantCreated takeaway],
      'brgen/app/models/takeaway/review.rb' => %w[TakeawayReviewCreated takeaway],
      'brgen/app/models/takeaway/favorite_restaurant.rb' => %w[TakeawayRestaurantFavorited takeaway],
      'brgen/app/models/takeaway/menu_item.rb' => %w[TakeawayMenuItemCreated takeaway],
      'brgen/app/models/tv/channel.rb' => %w[TvChannelCreated tv],
      'brgen/app/models/tv/video.rb' => %w[VideoUploaded tv],
      'brgen/app/models/tv/live_stream.rb' => %w[LiveStreamScheduled tv],
      'brgen/app/models/tv/show.rb' => %w[TvShowCreated tv],
      'brgen/app/models/tv/episode.rb' => %w[TvEpisodeCreated tv],
      'brgen/app/models/tv/broadcast.rb' => %w[BroadcastScheduled tv],
      'brgen/app/models/tv/comment.rb' => %w[TvCommentCreated tv],
      'brgen/app/models/tv/stream_chat.rb' => %w[TvStreamChatCreated tv],
      'brgen/app/models/tv/subscription.rb' => %w[TvChannelSubscribed tv],
      'brgen/app/models/tv/video_note.rb' => %w[TvVideoNoteCreated tv],
      'brgen/app/models/tv/view_event.rb' => %w[TvVideoViewed tv],
      'brgen/app/models/dating/profile.rb' => %w[DatingProfileCreated dating],
      'brgen/app/models/dating/dislike.rb' => %w[DatingDislike dating]
    }

    app_record = File.read(File.join(ROOT, 'shared/app/models/application_record.rb'))
    assert_includes app_record, 'include Shared::ActivityTrackable'

    expected_events.each do |relative, (event_name, vertical)|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'tracks_activity'
      assert_includes source, event_name
      assert_includes source, "source_vertical: \"#{vertical}\""
    end

    video_source = File.read(File.join(ROOT, 'brgen/app/models/tv/video.rb'))
    assert_includes video_source, 'VideoPublished'
    assert_includes video_source, 'saved_change_to_status?'

    broadcast_source = File.read(File.join(ROOT, 'brgen/app/models/tv/broadcast.rb'))
    assert_includes broadcast_source, 'BroadcastScheduled'
    assert_includes broadcast_source, 'BroadcastStarted'
    assert_includes broadcast_source, 'BroadcastEnded'
  end

  def test_marketplace_reviews_and_geo_localized_listings_are_wired
    migration = File.read(File.join(ROOT, 'brgen/db/migrate/20260707120000_create_marketplace_reviews_and_geo_listings.rb'))
    listing = File.read(File.join(ROOT, 'brgen/app/models/marketplace/listing.rb'))
    review = File.read(File.join(ROOT, 'brgen/app/models/marketplace/review.rb'))
    listings_controller = File.read(File.join(ROOT, 'brgen/app/controllers/marketplace/listings_controller.rb'))
    reviews_controller = File.read(File.join(ROOT, 'brgen/app/controllers/marketplace/reviews_controller.rb'))
    routes = File.read(File.join(ROOT, 'brgen/config/routes.rb'))
    index = File.read(File.join(ROOT, 'brgen/app/views/marketplace/listings/index.html.erb'))
    card = File.read(File.join(ROOT, 'brgen/app/views/marketplace/listings/_card.html.erb'))
    show = File.read(File.join(ROOT, 'brgen/app/views/marketplace/listings/show.html.erb'))

    assert_includes migration, 'create_table :marketplace_reviews'
    assert_includes migration, 'add_column :marketplace_listings, :latitude'
    assert_includes migration, 'add_column :marketplace_listings, :longitude'
    assert_includes migration, 'add_column :marketplace_listings, :reviews_count'
    assert_includes listing, 'has_many :reviews'
    assert_includes listing, 'include Shared::GeoLocatable'
    assert_includes listing, 'scope :near'
    assert_includes listing, 'reviewable_by?'
    assert_includes listing, 'update_rating!'
    assert_includes review, 'class Marketplace::Review'
    assert_includes review, 'MarketplaceReviewCreated'
    assert_includes review, 'buyer_has_completed_interaction'
    assert_includes review, 'seller_cannot_review_own_listing'
    assert_includes listings_controller, '@listing_distances'
    assert_includes listings_controller, 'Marketplace::Listing.radius_from'
    assert_includes reviews_controller, 'Marketplace::ReviewsController'
    assert_includes reviews_controller, 'reviewer_lat'
    assert_includes routes, 'resources :reviews, only: %i[create]'
    assert_includes index, ':radius_km'
    assert_includes card, 'km away'
    assert_includes card, 'reviews_count'
    assert_includes show, 'marketplace_listing_reviews_path'
    assert_includes show, '@reviews'
  end

  def test_playlist_import_embed_schema_trending_and_expiry_are_wired
    migration = File.read(File.join(ROOT, 'brgen/db/migrate/20260707121000_add_playlist_import_embed_and_expiry_fields.rb'))
    playlist = File.read(File.join(ROOT, 'brgen/app/models/playlist/playlist.rb'))
    track = File.read(File.join(ROOT, 'brgen/app/models/playlist/track.rb'))
    importer = File.read(File.join(ROOT, 'brgen/app/services/playlist/track_import_service.rb'))
    imports_controller = File.read(File.join(ROOT, 'brgen/app/controllers/playlist/imports_controller.rb'))
    playlists_controller = File.read(File.join(ROOT, 'brgen/app/controllers/playlist/playlists_controller.rb'))
    tracks_controller = File.read(File.join(ROOT, 'brgen/app/controllers/playlist/tracks_controller.rb'))
    routes = File.read(File.join(ROOT, 'brgen/config/routes.rb'))
    schema_helper = File.read(File.join(ROOT, 'shared/app/helpers/schema_helper.rb'))
    player = File.read(File.join(ROOT, 'brgen/app/views/playlist/playlists/_player.html.erb'))
    show = File.read(File.join(ROOT, 'brgen/app/views/playlist/playlists/show.html.erb'))
    index = File.read(File.join(ROOT, 'brgen/app/views/playlist/playlists/index.html.erb'))
    hosted_form = File.read(File.join(ROOT, 'brgen/app/views/playlist/hosted_tracks/_form.html.erb'))
    stimulus = File.read(File.join(ROOT, 'brgen/app/javascript/controllers/playlist_player_controller.js'))

    assert_includes migration, 'add_column :playlist_tracks, :expires_at'
    assert_includes migration, 'add_column :playlist_tracks, :privacy'
    assert_includes playlist, 'city_trending'
    assert_includes playlist, 'duration_seconds'
    assert_includes track, 'external_embed_url'
    assert_includes track, 'youtube_embed_url'
    assert_includes track, 'spotify_embed_url'
    assert_includes track, 'w.soundcloud.com/player'
    assert_includes importer, 'TrackImportService'
    assert_includes importer, 'youtube.com'
    assert_includes importer, 'spotify.com'
    assert_includes importer, 'soundcloud.com'
    assert_includes imports_controller, 'require_user_session'
    assert_includes imports_controller, 'return if performed?'
    assert_includes playlists_controller, 'def embed'
    assert_includes playlists_controller, 'Playlist::Track.unexpired'
    assert_includes tracks_controller, ':expires_at'
    assert_includes routes, 'member { get :embed }'
    assert_includes routes, 'resources :imports, only: :create'
    assert_includes schema_helper, 'MusicPlaylist'
    assert_includes schema_helper, 'MusicRecording'
    assert_includes schema_helper, 'iso8601_duration'
    assert_includes player, 'itemtype="https://schema.org/MusicPlaylist"'
    assert_includes player, 'data-playlist-player-embed-param'
    assert_includes player, 'playlist-embed-frame'
    assert_includes stimulus, 'embedTarget'
    assert_includes show, 'json_ld_for(@playlist, type: :music_playlist)'
    assert_includes show, 'playlist_playlist_imports_path'
    assert_includes show, 'embed_playlist_playlist_url'
    assert_includes hosted_form, 'form.datetime_field :expires_at'
  end

  def test_takeaway_geocoding_menu_availability_and_order_state_machine_are_wired
    migration = File.read(File.join(ROOT, 'brgen/db/migrate/20260707122000_harden_takeaway_geo_availability_and_orders.rb'))
    restaurant = File.read(File.join(ROOT, 'brgen/app/models/takeaway/restaurant.rb'))
    menu_item = File.read(File.join(ROOT, 'brgen/app/models/takeaway/menu_item.rb'))
    order = File.read(File.join(ROOT, 'brgen/app/models/takeaway/order.rb'))
    order_item = File.read(File.join(ROOT, 'brgen/app/models/takeaway/order_item.rb'))
    restaurants_controller = File.read(File.join(ROOT, 'brgen/app/controllers/takeaway/restaurants_controller.rb'))
    orders_controller = File.read(File.join(ROOT, 'brgen/app/controllers/takeaway/orders_controller.rb'))
    new_view = File.read(File.join(ROOT, 'brgen/app/views/takeaway/restaurants/new.html.erb'))
    restaurant_show = File.read(File.join(ROOT, 'brgen/app/views/takeaway/restaurants/show.html.erb'))
    order_show = File.read(File.join(ROOT, 'brgen/app/views/takeaway/orders/show.html.erb'))

    assert_includes migration, 'change_column_default :takeaway_menu_items, :available'
    assert_includes migration, 'add_index :takeaway_restaurants, %i[latitude longitude]'
    assert_includes restaurant, 'require "zlib"'
    assert_includes restaurant, 'before_validation :geocode_if_needed'
    assert_includes restaurant, 'stable_coordinate_offsets'
    assert_includes restaurant, 'City.find_by(id: self[:city_id])'
    assert_includes menu_item, 'available_for_order?'
    assert_includes menu_item, 'self.available = true if available.nil?'
    assert_includes order_item, 'menu_item_must_be_available'
    assert_includes order, 'TRANSITIONS ='
    assert_includes order, 'transition_to!'
    assert_includes order, 'status_transition_allowed'
    assert_includes order, 'status_in_database'
    assert_includes restaurants_controller, ':latitude'
    assert_includes restaurants_controller, ':longitude'
    assert_includes orders_controller, 'menu_items.available.find_by'
    assert_includes orders_controller, 'params[:status].presence'
    assert_includes new_view, 'f.number_field :latitude'
    assert_includes restaurant_show, 'f.check_box :available'
    assert_includes restaurant_show, 'item.vegan?'
    assert_includes order_show, 'Takeaway::Order::TRANSITIONS.fetch'
  end

  def test_queue_failure_summary_and_digest_schedule
    rows = [
      { class_name: 'ExampleJob', queue_name: 'bulk', failures: 3, last_failed_at: '2026-01-01 04:00:00' }
    ]
    summary = Shared::QueueFailureSummary.call(rows, app: 'brgen')
    assert_includes summary, 'ExampleJob (bulk): 3 failure(s)'
    assert_includes summary, 'brgen queue dead letters'

    source = File.read(File.join(ROOT, 'brgen/config/recurring.yml'))
    assert_includes source, 'queue_failure_digest:'
    assert_includes source, 'class: QueueFailureDigestJob'
    assert_includes source, 'schedule: every day at 5am'

    job_source = File.read(File.join(ROOT, 'brgen/app/jobs/queue_failure_digest_job.rb'))
    assert_includes job_source, 'solid_queue_failed_executions'
    assert_includes job_source, 'QueueFailureMailer.daily_digest'
  end

  def test_cable_health_alert_trips_at_one_thousand_connections
    assert Shared::CableHealth.alert?(connection_count: 1_001, max_connections: 1_000)
    refute Shared::CableHealth.alert?(connection_count: 999, max_connections: 1_000)
    assert_equal 'brgen cable at 1001/1000 connections',
                 Shared::CableHealth.message(app: 'brgen', connection_count: 1_001, max_connections: 1_000)
  end

  def test_turbo_navigation_and_cache_controls_are_explicit
    hotwire = File.read(File.join(ROOT, 'shared/frontend/hotwire.js'))
    assert_includes hotwire, 'Turbo.config.drive.progressBarDelay = 100'

    %w[
      amber/app/javascript/application.js
      bsdports/app/javascript/application.js
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'import "pub4/hotwire"'
    end

    assert_includes File.read(File.join(ROOT, 'brgen/app/assets/javascripts/face.js')),
                    'Turbo.config.drive.progressBarDelay = 100'

    %w[
      amber/app/views/layouts/application.html.erb
      bsdports/app/views/layouts/application.html.erb
      brgen/app/views/layouts/application.html.erb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'data-turbo-permanent'
      refute_includes source, 'turbo-cache-control", content: "no-cache"'

      # Amber factors the sign-out link (and its turbo_prefetch:
      # false safety attribute — prevents a hover-prefetch from firing the
      # DELETE) into shared/_sidebar_nav.html.erb rather than inlining it in
      # the layout; check that partial too when the layout itself doesn't.
      app_dir = relative.split("/").first
      nav_partial = File.join(ROOT, app_dir, "app/views/shared/_sidebar_nav.html.erb")
      haystack = source
      haystack += File.read(nav_partial) if File.file?(nav_partial)
      assert_includes haystack, 'turbo_prefetch: false'
    end

    setup = File.read(File.join(ROOT, 'shared/app/controllers/concerns/shared/application_setup.rb'))
    assert_includes setup, 'turbo_refreshes_with :morph, scroll: :preserve'

    source = File.read(File.join(ROOT, 'shared/frontend/layouts/_nav.html.erb'))
    assert_includes source, 'data-turbo-permanent'
    assert_includes source, 'turbo_prefetch: false'

    pagy_source = File.read(File.join(ROOT, 'shared/config/initializers/pagy.rb'))
    assert_includes pagy_source, 'data-turbo-prefetch="false"'
    assert_includes pagy_source, 'rel="prefetch"'
  end

  def test_sqlite_wal_and_shared_stimulus_components_are_present
    %w[
      amber/config/database.yml
      brgen/config/database.yml
      bsdports/config/database.yml
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'journal_mode: WAL'
    end

    source = File.read(File.join(ROOT, 'shared/config/environments/development.rb'))
    assert_includes source, 'strict_loading_by_default = true'

    source = File.read(File.join(ROOT, 'shared/frontend/stimulus_boot.js'))
    %w[
      Clipboard
      Dialog
      Dropdown
      Hotkey
      Notification
      Reveal
      Sortable
      toast
      TextareaAutogrow
      Timeago
      PasswordVisibility
      RailsNestedForm
      Carousel
      CharacterCounter
      CheckboxSelectAll
      ReadMore
    ].each do |component|
      assert_includes source, component
    end

    assert_includes File.read(File.join(ROOT, 'shared/app/views/shared/_toast.html.erb')), 'data-controller="toast"'
    assert_includes File.read(File.join(ROOT, 'shared/frontend/examples.html.erb')), 'data-controller="toast"'

    wardrobe_form = File.read(File.join(ROOT, 'amber/app/views/wardrobe_items/_form.html.erb'))
    assert wardrobe_form.include?('textarea-autogrow') || wardrobe_form.include?('character-counter')
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/comments/_form.html.erb')), 'textarea-autogrow'
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/posts/_post.html.erb')), 'cache [post, Current.user&.id]'
    assert_includes File.read(File.join(ROOT, 'amber/app/views/posts/_post.html.erb')), 'cache [post, Current.user&.id, post.anonymous?]'
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/posts/_post.html.erb')), 'data-controller="clipboard"'
    assert_includes File.read(File.join(ROOT, 'shared/app/views/shared/_copyable.html.erb')),
                    'data-controller="clipboard"'

    helper_source = File.read(File.join(ROOT, 'amber/app/helpers/application_helper.rb'))
    assert_includes helper_source, 'content_tag(:picture)'
    assert_includes helper_source, 'type: "image/webp"'
    assert_includes helper_source, 'loading: "lazy"'
    assert_includes helper_source, 'responsive_image_url'
    assert_includes File.read(File.join(ROOT, 'amber/app/views/items/show.html.erb')), 'responsive_image_tag photo'
    assert_includes File.read(File.join(ROOT, 'amber/app/views/outfits/dressing_room.html.erb')),
                    'responsive_image_url(item.photos.first'

    %w[
      brgen/app/views/pwa/manifest.json.erb
      amber/app/views/pwa/manifest.json.erb
      bsdports/app/views/pwa/manifest.json.erb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, '"shortcuts"'
    end

    assert_includes File.read(File.join(ROOT, 'brgen/app/views/pwa/manifest.json.erb')), 'New listing'
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/pwa/manifest.json.erb')), '"protocol_handlers"'
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/pwa/manifest.json.erb')), 'web+brgen'
    assert_includes File.read(File.join(ROOT, 'brgen/app/javascript/controllers/push_controller.js')),
                    'navigator.setAppBadge'
    assert_includes File.read(File.join(ROOT, 'brgen/app/javascript/controllers/push_controller.js')),
                    'navigator.clearAppBadge'
    assert_includes File.read(File.join(ROOT, 'shared/pwa/service_worker.js')), 'setAppBadge'
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/pwa/service-worker.js')), 'workbox:core'
    brgen_layout = File.read(File.join(ROOT, 'brgen/app/views/layouts/application.html.erb'))
    assert_includes brgen_layout, 'data-push-unread-value='
    assert_includes brgen_layout, 'render "shared/ai_nav_link"'
    assert_includes brgen_layout, 'brgen_ai_url'
    refute_includes brgen_layout, 'javascript_include_tag "face"'
    refute_includes brgen_layout, 'javascript_include_tag "particle_kernel"'
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/pwa/manifest.json.erb')), 'AI assistant'
    assert_includes File.read(File.join(ROOT, 'brgen/app/views/pwa/manifest.json.erb')), 'brgen_ai_url'
    assert_includes File.read(File.join(ROOT, 'amber/app/views/pwa/manifest.json.erb')), 'Create outfit'
    assert_includes File.read(File.join(ROOT, 'bsdports/app/views/pwa/manifest.json.erb')), 'Search ports'
    assert_includes File.read(File.join(ROOT, 'amber/app/views/pwa/manifest.json.erb')), '"file_handlers"'
    assert_includes File.read(File.join(ROOT, 'amber/app/views/pwa/manifest.json.erb')), 'image/*'

    ports_controller = File.read(File.join(ROOT, 'bsdports/app/controllers/ports_controller.rb'))
    assert_includes ports_controller, 'expires_in 10.minutes, public: true'
    assert_includes ports_controller, 'fresh_when(@port, public: true)'

    source = File.read(File.join(ROOT, 'brgen/config/recurring.yml'))
    assert_includes source, 'cable_health_check:'
    assert_includes source, 'class: CableHealthJob'
    assert_includes source, 'schedule: every hour at minute 7'
  end

  def test_brgen_users_maps_checkins_and_listening_parties_are_wired
    routes = File.read(File.join(ROOT, 'brgen/config/routes.rb'))
    migration = File.read(File.join(ROOT, 'brgen/db/migrate/20260708120000_create_maps_check_ins_and_listening_parties.rb'))

    assert_includes routes, 'resources :users, only: [ :show ]'
    assert_includes routes, 'post :check_in'
    assert_includes routes, 'resource :listening_party'
    assert_includes migration, 'create_table :place_check_ins'
    assert_includes migration, 'create_table :playlist_listening_parties'
    assert_includes migration, 'idx_party_messages_on_party_and_created_at'
    assert_includes read_brgen('app/controllers/users_controller.rb'), 'def show'
    assert_includes read_brgen('app/controllers/maps/places_controller.rb'), 'def check_in'
    assert_includes read_brgen('app/controllers/playlist/listening_parties_controller.rb'), 'def create'
    assert_includes read_brgen('app/views/users/show.html.erb'), 'follow_button'
    assert_includes read_brgen('app/views/maps/places/show.html.erb'), 'check_in_maps_place_path'
    assert_includes read_brgen('app/views/playlist/sets/show.html.erb'), 'playlist_set_listening_party_path'
  end

  def test_bsdports_security_advisory_refresh_job_uses_nvd_service
    job = File.read(File.join(ROOT, 'bsdports/app/jobs/security_advisory_refresh_job.rb'))
    recurring = File.read(File.join(ROOT, 'bsdports/config/recurring.yml'))

    assert_includes job, 'NvdCveService.crossref'
    assert_includes job, 'CURSOR_KEY'
    assert_includes recurring, 'SecurityAdvisoryRefreshJob'
  end

  def test_shared_auth_fields_migrated_across_rails_apps
    %w[amber brgen bsdports].each do |app|
      migration = File.join(ROOT, app, 'db/migrate/20260709120000_add_shared_auth_fields_to_users.rb')
      assert File.file?(migration), "missing shared auth migration for #{app}"

      source = File.read(migration)
      assert_includes source, ':remember_token'
      assert_includes source, ':magic_link_token'
      assert_includes source, ':two_factor_enabled'
    end

    initializer = File.read(File.join(ROOT, 'shared/config/initializers/auth_extensions.rb'))
    assert_includes initializer, 'Shared::UserAuthExtensions'
    assert_includes File.read(File.join(ROOT, 'shared/app/models/concerns/shared/user_auth_extensions.rb')),
                    'ensure_auth_column!'
  end

  def test_playlist_tracks_schema_includes_user_ownership
    schema = File.read(File.join(ROOT, 'brgen/db/schema.rb'))
    assert_includes schema, 'create_table "playlist_tracks"'
    assert_includes schema, 't.integer "user_id"', 'brgen schema missing playlist_tracks.user_id'
    assert_includes schema, 'index_playlist_tracks_on_user_id'
    assert_includes schema, 'add_foreign_key "playlist_tracks", "users"'
  end

  def test_schema_dumps_include_shared_auth_user_columns
    %w[amber brgen bsdports].each do |app|
      schema = File.read(File.join(ROOT, app, 'db', 'schema.rb'))
      assert_includes schema, 't.string "remember_token"', "#{app} schema missing remember_token"
      assert_includes schema, 't.string "magic_link_token"', "#{app} schema missing magic_link_token"
      assert_includes schema, 't.boolean "two_factor_enabled"', "#{app} schema missing two_factor_enabled"
      assert_includes schema, 'index_users_on_remember_token', "#{app} schema missing remember_token index"
    end
  end

  def test_messenger_subdomain_routes_conversations_and_messages
    routes = File.read(File.join(ROOT, 'brgen/config/routes.rb'))
    assert_includes routes, 'constraints(subdomain: MESSENGER_SUBDOMAINS)'
    assert_includes routes, 'as: :messenger_root'
    assert_includes routes, 'resources :conversations, only: %i[show update create]'
    assert_includes routes, 'resources :messages, only: %i[create]'
  end

  def test_marketplace_listings_use_stimulus_reflex_infinite_scroll
    partial = read_brgen('app/views/marketplace/listings/_live_search_results.html.erb')
    reflex = read_brgen('app/reflexes/listings_infinite_scroll_reflex.rb')

    assert_includes partial, 'ListingsInfiniteScrollReflex#load_more'
    assert_includes partial, 'marketplace-listings-sentinel'
    assert_includes reflex, 'class ListingsInfiniteScrollReflex'
    assert_includes reflex, 'marketplace/listings/card'
  end

  def test_playlist_tracks_and_hosted_tracks_wire_user_ownership
    migration = read_brgen('db/migrate/20260709120100_add_user_to_playlist_tracks.rb')
    track = read_brgen('app/models/playlist/track.rb')
    hosted = read_brgen('app/controllers/playlist/hosted_tracks_controller.rb')
    tracks_controller = read_brgen('app/controllers/playlist/tracks_controller.rb')

    assert_includes migration, 'add_reference :playlist_tracks, :user'
    assert_includes track, 'belongs_to :user'
    assert_includes hosted, '@track.user = Current.user'
    assert_includes tracks_controller, 'user: Current.user'
  end

  def test_home_feed_uses_stimulus_reflex_infinite_scroll
    home = read_brgen('app/controllers/home_controller.rb')
    partial = read_brgen('app/views/home/_live_search_results.html.erb')
    reflex = read_brgen('app/reflexes/home_infinite_scroll_reflex.rb')

    assert_includes home, '@pagy, @posts = pagy(scope)'
    assert_includes partial, 'HomeInfiniteScrollReflex#load_more'
    assert_includes partial, 'home-feed-sentinel'
    assert_includes reflex, 'Brgen::HomeFeed.scope'
  end

  def test_takeaway_and_tv_indexes_use_infinite_scroll_reflexes
    restaurants = read_brgen('app/views/takeaway/restaurants/_live_search_results.html.erb')
    channels = read_brgen('app/views/tv/channels/_live_search_results.html.erb')

    assert_includes restaurants, 'RestaurantsInfiniteScrollReflex#load_more'
    assert_includes restaurants, 'takeaway-restaurants-sentinel'
    assert_includes channels, 'ChannelsInfiniteScrollReflex#load_more'
    assert_includes channels, 'tv-channels-sentinel'
    assert_includes File.read(File.join(ROOT, 'brgen/app/reflexes/restaurants_infinite_scroll_reflex.rb')),
                    'takeaway/restaurants/card'
    assert_includes File.read(File.join(ROOT, 'brgen/app/reflexes/channels_infinite_scroll_reflex.rb')),
                    'tv/channels/row'
  end

  def test_maps_places_browse_and_infinite_scroll_are_wired
    controller = read_brgen('app/controllers/maps/places_controller.rb')
    index = read_brgen('app/views/maps/places/index.html.erb')
    partial = read_brgen('app/views/maps/places/_live_search_results.html.erb')
    reflex = read_brgen('app/reflexes/places_infinite_scroll_reflex.rb')
    home = read_brgen('app/views/maps/home/index.html.erb')

    assert_includes controller, 'format.html'
    assert_includes controller, '@pagy, @places = pagy'
    assert_includes index, 'maps_places_path'
    assert_includes partial, 'PlacesInfiniteScrollReflex#load_more'
    assert_includes reflex, 'maps/places/card'
    assert_includes home, 'maps_places_path'
  end

  def test_messenger_compose_flow_accepts_username
    index = read_brgen('app/views/conversations/index.html.erb')
    controller = read_brgen('app/controllers/conversations_controller.rb')

    assert_includes index, 'messenger-compose'
    assert_includes index, 'f.text_field :username'
    assert_includes controller, 'resolve_conversation_partner'
    assert_includes controller, 'params[:username]'
  end

  def test_sitemap_routes_and_shared_builder_across_rails_apps
    sentinel = File.read(File.join(ROOT, 'shared/app/views/shared/_infinite_scroll_sentinel.html.erb'))
    builder = File.read(File.join(ROOT, 'shared/app/services/shared/sitemap_builder.rb'))

    assert_includes sentinel, 'data-cuisine'
    assert_includes sentinel, 'data-kind'
    assert_includes builder, 'Builder::XmlMarkup'

    %w[amber brgen bsdports].each do |app|
      routes = File.read(File.join(ROOT, "#{app}/config/routes.rb"))
      assert_includes routes, 'sitemaps#index', "#{app} missing sitemap route"
      assert File.file?(File.join(ROOT, app, 'app/controllers/sitemaps_controller.rb')),
             "#{app} missing SitemapsController"
      source = File.read(File.join(ROOT, app, 'app/controllers/sitemaps_controller.rb'))
      assert_includes source, 'Shared::Sitemapable'
      assert_includes source, 'sitemap_entries'
    end

    brgen_routes = File.read(File.join(ROOT, 'brgen/config/routes.rb'))
    assert_includes brgen_routes, 'robots#show'
    assert_includes read_brgen('app/controllers/sitemaps_controller.rb'), 'Brgen::DomainRegistry.resolve'
  end

  def test_marketplace_deals_stores_and_playlist_sets_use_infinite_scroll
    deals_partial = read_brgen('app/views/marketplace/deals/_live_search_results.html.erb')
    stores_partial = read_brgen('app/views/marketplace/stores/_live_search_results.html.erb')
    sets_partial = read_brgen('app/views/playlist/sets/_live_search_results.html.erb')

    assert_includes deals_partial, 'DealsInfiniteScrollReflex#load_more'
    assert_includes stores_partial, 'StoresInfiniteScrollReflex#load_more'
    assert_includes sets_partial, 'SetsInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/controllers/marketplace/deals_controller.rb'), '@pagy, @deals = pagy'
    assert_includes read_brgen('app/controllers/marketplace/stores_controller.rb'), '@pagy, @stores = pagy'
    assert_includes read_brgen('app/controllers/playlist/sets_controller.rb'), '@pagy, @sets = pagy'
    assert_includes read_brgen('app/reflexes/deals_infinite_scroll_reflex.rb'), 'marketplace/deals/card'
    assert_includes read_brgen('app/reflexes/stores_infinite_scroll_reflex.rb'), 'marketplace/stores/card'
    assert_includes read_brgen('app/reflexes/sets_infinite_scroll_reflex.rb'), 'playlist/sets/card'
  end

  def test_communities_infinite_scroll_and_crud_views_are_wired
    partial = read_brgen('app/views/communities/_live_search_results.html.erb')
    controller = read_brgen('app/controllers/communities_controller.rb')

    assert_includes partial, 'CommunitiesInfiniteScrollReflex#load_more'
    assert_includes controller, '@pagy, @communities = pagy'
    assert_includes controller, 'def edit'
    assert_includes controller, 'def update'
    assert_includes controller, 'def destroy'
    assert File.file?(File.join(ROOT, 'brgen/app/views/communities/edit.html.erb'))
    assert_includes read_brgen('app/reflexes/communities_infinite_scroll_reflex.rb'), 'communities/card'
    assert_includes File.read(File.join(ROOT, 'brgen/app/assets/stylesheets/_communities.scss')), '.community-list'
  end

  def test_playlist_set_likes_controller_and_ui_are_wired
    controller = read_brgen('app/controllers/playlist/likes_controller.rb')
    show = read_brgen('app/views/playlist/sets/show.html.erb')

    assert_includes controller, 'class Playlist::LikesController'
    refute_includes controller, 'module Playlist'
    assert_includes controller, 'find_or_create_by!'
    assert_includes controller, 'destroy_all'
    assert_includes show, 'playlist_set_like_path'
    assert_includes show, 'likes.count'
  end

  def test_posts_infinite_scroll_preserves_search_query
    partial = read_brgen('app/views/posts/_live_search_results.html.erb')
    reflex = read_brgen('app/reflexes/posts_infinite_scroll_reflex.rb')

    assert_includes partial, 'q: params[:q]'
    assert_includes reflex, 'element.dataset["q"]'
    assert_includes reflex, 'title LIKE ? OR content LIKE ?'
  end

  def test_marketplace_stores_edit_update_destroy_are_wired
    controller = read_brgen('app/controllers/marketplace/stores_controller.rb')

    assert_includes controller, 'def edit'
    assert_includes controller, 'def update'
    assert_includes controller, 'def destroy'
    assert_includes controller, 'authorize_owner'
    assert File.file?(File.join(ROOT, 'brgen/app/views/marketplace/stores/edit.html.erb'))
    assert_includes read_brgen('app/assets/stylesheets/_marketplace_stores.scss'), '.store-grid'
    assert_includes read_brgen('app/assets/stylesheets/application.scss'), '_marketplace_stores'
  end

  def test_secondary_brgen_verticals_use_infinite_scroll_reflexes
    sentinel = File.read(File.join(ROOT, 'shared/app/views/shared/_infinite_scroll_sentinel.html.erb'))
    assert_includes sentinel, 'data-channel-slug'

    assert_includes read_brgen('app/views/tv/channels/_channel_videos.html.erb'), 'ChannelVideosInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/reflexes/channel_videos_infinite_scroll_reflex.rb'), 'tv/videos/tv_video'

    assert_includes read_brgen('app/views/tv/home/_trending_videos.html.erb'), 'TrendingVideosInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/reflexes/trending_videos_infinite_scroll_reflex.rb'), 'Tv::Video.trending'

    assert_includes read_brgen('app/views/takeaway/orders/index.html.erb'), 'OrdersInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/reflexes/orders_infinite_scroll_reflex.rb'), 'takeaway/orders/order'

    assert_includes read_brgen('app/views/dating/matches/index.html.erb'), 'MatchesInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/reflexes/matches_infinite_scroll_reflex.rb'), 'dating/matches/match'

    assert_includes read_brgen('app/views/marketplace/categories/show.html.erb'), 'CategoryListingsInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/reflexes/category_listings_infinite_scroll_reflex.rb'), 'marketplace/listings/card'

    assert_includes read_brgen('app/views/tv/shows/index.html.erb'), 'ShowsInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/reflexes/shows_infinite_scroll_reflex.rb'), 'tv/shows/card'

    assert_includes read_brgen('app/views/playlist/playlists/_library.html.erb'), 'PlaylistsInfiniteScrollReflex#load_more'
    assert_includes read_brgen('app/reflexes/playlists_infinite_scroll_reflex.rb'), 'playlist/playlists/row'
    assert_includes read_brgen('app/assets/stylesheets/_vertical_tv.scss'), '.show-grid'
    assert_includes read_brgen('app/assets/stylesheets/_vertical_takeaway.scss'), '.order-list'
    assert_includes read_brgen('app/assets/stylesheets/_vertical_dating_shell.scss'), '.match-list'
  end

  def test_satellite_apps_use_infinite_scroll_reflexes
    sentinel = File.read(File.join(ROOT, 'shared/app/views/shared/_infinite_scroll_sentinel.html.erb'))

    assert_includes File.read(File.join(ROOT, 'amber/app/views/items/_live_search_results.html.erb')),
                    'ItemsInfiniteScrollReflex#load_more'
    assert_includes File.read(File.join(ROOT, 'amber/app/reflexes/items_infinite_scroll_reflex.rb')),
                    'items/item'

    assert_includes File.read(File.join(ROOT, 'amber/app/views/outfits/_live_search_results.html.erb')),
                    'OutfitsInfiniteScrollReflex#load_more'
    assert_includes File.read(File.join(ROOT, 'amber/app/reflexes/outfits_infinite_scroll_reflex.rb')),
                    'outfits/outfit'

    assert_includes File.read(File.join(ROOT, 'bsdports/app/views/ports/_live_search_results.html.erb')),
                    'PortsInfiniteScrollReflex#load_more'
    assert_includes File.read(File.join(ROOT, 'bsdports/app/reflexes/ports_infinite_scroll_reflex.rb')),
                    'ports/row'

    assert_includes File.read(File.join(ROOT, 'bsdports/app/views/maintainers/show.html.erb')),
                    'MaintainerPortsInfiniteScrollReflex#load_more'
    assert_includes sentinel, 'data-maintainer-id'
  end

  def test_brgen_visual_polish_stack_is_wired
    layout = read_brgen('app/views/layouts/application.html.erb')
    scss = read_brgen('app/assets/stylesheets/application.scss')
    manifest = read_brgen('app/views/pwa/manifest.json.erb')
    show = read_brgen('app/views/posts/show.html.erb')
    app_js = read_brgen('app/javascript/application.js')

    assert_includes layout, 'yield :splash'
    assert_includes layout, 'id="splash"'
    assert_includes layout, '#17161c'
    assert_includes manifest, '"theme_color": "#17161c"'
    assert_includes scss, '_x_card_modifiers'
    assert_includes scss, '_chrome_polish'
    assert_includes scss, 'offline_page'
    assert_includes read_brgen('app/assets/stylesheets/_vertical_playlist.scss'), '.playlist-top'
    assert_includes read_brgen('app/assets/stylesheets/_vertical_tv.scss'), '.tv-live-streams'
    assert_includes show, 'x-post-show'
    assert_includes show, 'x_feed_icon'
    refute_includes show, 'post_show'
    assert_includes app_js, 'brgen_shell'
    assert_includes read_brgen('config/importmap.rb'), 'brgen_shell'
    assert_includes File.read(File.join(ROOT, 'shared/app/assets/stylesheets/_x_base.scss')), '--x-radius-card: 16px'
    refute File.exist?(File.join(ROOT, 'brgen/app/controllers/playlist_controller.rb'))
    refute File.exist?(File.join(ROOT, 'brgen/app/views/shared/_vote.html.erb'))
    assert_includes File.read(File.join(ROOT, '_deploy.sh')), 'DEMO_SEED_ON_DEPLOY'
    assert_includes File.read(File.join(ROOT, 'shared/config/initializers/omniauth.rb')), ':snapchat'
    refute_includes read_brgen('app/assets/stylesheets/_posts.scss'), '.post_show'
    assert_includes read_brgen('app/assets/stylesheets/_nav.scss'), 'border-bottom-color: var(--accent)'
    assert_includes read_brgen('app/views/layouts/application.html.erb'), 'unless vertical_surface?'
  end

  def test_demo_seed_media_uses_shared_postpro_pipeline
    assert_includes File.read(File.join(ROOT, "shared/app/services/shared/demo_media.rb")), "attach_remote_postpro!"
    assert_includes File.read(File.join(ROOT, "shared/app/services/shared/postpro_processor.rb")), "PostproProcessor"
    assert_includes read_brgen("lib/brgen/bergen_demo_seeder.rb"), "attach_remote_postpro!"
    assert_includes File.read(File.join(ROOT, "amber/lib/amber/amber_demo_seeder.rb")), "attach_remote_postpro!"
    assert_includes File.read(File.join(ROOT, "amber/app/jobs/wardrobe_media_job.rb")), "PostproProcessor.apply_to_record!"
  end

  def test_brgen_views_have_valid_page_header_open_tags
    offenders = Dir[File.join(ROOT, 'brgen/app/views/**/*.html.erb')].select do |path|
      File.read(path).match?(/^(div|header) class="page-header"/m)
    end
    assert_empty offenders, "broken page-header open tags (missing '<'): #{offenders.map { |p| p.sub(%r{.*brgen/}, '') }.join(', ')}"
  end

  private

  def read_brgen(relative)
    File.read(File.join(ROOT, 'brgen', relative))
  end
end
