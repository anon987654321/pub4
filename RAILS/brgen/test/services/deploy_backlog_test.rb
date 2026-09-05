# frozen_string_literal: true

require "minitest/autorun"
require_relative "../source_reader"
require_relative "../../../shared/app/services/shared/cache_policy"
require_relative "../../../shared/app/services/shared/cache_health"
require_relative "../../../shared/app/services/shared/cable_health"
require_relative "../../../shared/app/services/shared/queue_failure_summary"

class DeployBacklogTest < Minitest::Test
  include SourceReader

  # Every assertion in this file and in InfiniteScrollWiringTest reads a file
  # through ROOT, so ROOT resolving anywhere else turns the lot into ENOENT — 39
  # errors and 1043 assertions that never ran, on any checkout that is not
  # /home/dev/pub4. The box hits the first candidate, so the box never saw it.
  # Named here rather than left to the reads, because a wrong ROOT fails as a
  # missing file and reads as a missing file.
  def test_root_resolves_to_the_rails_tree
    assert File.directory?(File.join(ROOT, "shared", "app")), "ROOT=#{ROOT} has no shared/app"
    assert File.directory?(File.join(ROOT, "brgen", "app")), "ROOT=#{ROOT} has no brgen/app"
    assert_equal "RAILS", File.basename(ROOT)
  end

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
      source = read_source(File.join(ROOT, relative))
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
    assert_match(/brgen cache at 81.0%/, Shared::CacheHealth.message(app: "brgen", bytes_used: 81, max_size_bytes: 100))
  end

  def test_cache_health_job_is_scheduled
    source = read_source(File.join(ROOT, "brgen/config/recurring.yml"))
    assert_includes source, "cache_health_check:"
    assert_includes source, "class: CacheHealthJob"
    assert_includes source, "schedule: every day at 4am"
  end

  def test_omniauth_wires_installed_providers_to_identity_primitives
    initializer = read_source(File.join(ROOT, "shared/config/initializers/omniauth.rb"))
    callback = read_source(File.join(ROOT, "shared/app/controllers/omniauth_callbacks_controller.rb"))
    links = read_source(File.join(ROOT, "shared/app/views/shared/_oauth_links.html.erb"))

    assert_includes initializer, ":google_oauth2"
    assert_includes initializer, ":github"
    assert_includes initializer, ":vipps"
    assert_includes initializer, ":snapchat"
    assert_includes initializer, "oauth_provider_slugs"
    assert_includes callback, "persist_external_identity"
    assert_includes callback, "IdentityProvider.find_or_create_by!"
    assert_includes callback, "ExternalIdentity.table_exists?"
    assert_includes callback, "Shared::Authentication.table_exists?"
    assert_includes links, "oauth_provider_slugs"
    assert_includes links, "/auth/google_oauth2"
    assert_includes links, "/auth/snapchat"
  end

  def test_nearby_geolocation_uses_explicit_radius_and_exact_distance
    nearby = read_source(File.join(ROOT, "brgen/app/controllers/nearby_controller.rb"))
    locations = read_source(File.join(ROOT, "brgen/app/controllers/locations_controller.rb"))
    geolocation = read_source(File.join(ROOT, "shared/frontend/geolocation_controller.js"))
    layout = read_source(File.join(ROOT, "brgen/app/views/layouts/application.html.erb"))
    nearby_view = read_source(File.join(ROOT, "brgen/app/views/nearby/index.html.erb"))
    dating_matchmaking = read_source(File.join(ROOT, "brgen/app/services/dating/matchmaking.rb"))

    assert_includes nearby, "DEFAULT_RADIUS_KM = 10.0"
    assert_includes nearby, "MAX_RADIUS_KM = 25.0"
    assert_includes nearby, "value.to_f.clamp(0.5, MAX_RADIUS_KM)"
    assert_includes nearby, "distance > radius"
    assert_includes locations, "ALERT_RADIUS_KM = NearbyController::DEFAULT_RADIUS_KM"
    assert_includes locations, "other.distance_to(lat, lng).to_f > ALERT_RADIUS_KM"
    assert_includes geolocation, "radiusKm"
    assert_includes geolocation, 'credentials: "same-origin"'
    assert_includes layout, "data-geolocation-radius-km-value="
    assert_includes nearby_view, "number_with_precision(distance, precision: 1)"
    assert_includes dating_matchmaking, "radius_km: DEFAULT_RADIUS_KM"
  end

  def test_moderation_reports_create_flags_and_reputation_effects
    workflow = read_source(File.join(ROOT, "brgen/app/services/moderation_workflow.rb"))
    reports = read_source(File.join(ROOT, "brgen/app/controllers/reports_controller.rb"))
    admin = read_source(File.join(ROOT, "brgen/app/controllers/admin/reports_controller.rb"))

    assert_includes reports, "ModerationWorkflow.report!"
    assert_includes admin, "ModerationWorkflow.transition!"
    assert_includes workflow, "ModerationReport.create!"
    assert_includes workflow, "ModerationFlag.where"
    assert_includes workflow, "flag.save!"
    assert_includes workflow, "update_all(status: status"
    assert_includes workflow, 'kind: "spam_report"'
    assert_includes workflow, "TrustScore.new(user: user).call"
    assert_includes workflow, "accountable_user"
  end

  def test_media_pipeline_processes_image_variants_across_upload_surfaces
    concern = read_source(File.join(ROOT, "shared/app/models/concerns/shared/media_processable.rb"))
    job = read_source(File.join(ROOT, "shared/app/jobs/shared/media_processing_job.rb"))

    assert_includes concern, "process_media_variants"
    assert_includes concern, "after_commit :enqueue_media_variant_processing"
    refute_includes concern.gsub(/^\s*#.*\n/, ""), "perform_later"
    assert_includes concern, "Shared::MediaProcessingJob.new.perform"
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
      source = read_source(File.join(ROOT, relative))
      assert_includes source, "include Shared::MediaProcessable"
      assert_includes source, "process_media_variants"
      assert_includes source, "format: :webp"
    end

    helper_source = read_source(File.join(ROOT, "brgen/app/helpers/application_helper.rb"))
    assert_includes helper_source, "lazy_image_blurhash_value"
    assert_includes helper_source, "responsive_image_tag"
  end

  def test_activity_graph_emits_across_vertical_models
    concern = read_source(File.join(ROOT, "shared/app/models/concerns/shared/activity_trackable.rb"))
    assert_includes concern, "Shared::DomainEvent.record!"
    assert_includes concern, "legacy_event_name"

    expected_events = {
      "brgen/app/models/playlist/playlist.rb" => %w[PlaylistCreated playlist],
      "brgen/app/models/playlist/set.rb" => %w[PlaylistSetCreated playlist],
      "brgen/app/models/playlist/track.rb" => %w[PlaylistTrackCreated playlist],
      "brgen/app/models/playlist/listen.rb" => %w[PlaylistListen playlist],
      "brgen/app/models/playlist/like.rb" => %w[PlaylistLiked playlist],
      "brgen/app/models/playlist/collaboration.rb" => %w[PlaylistCollaborationCreated playlist],
      "brgen/app/models/playlist/dilla_sketch.rb" => %w[DillaSketchCreated playlist],
      "brgen/app/models/marketplace/store.rb" => %w[MarketplaceStoreCreated marketplace],
      "brgen/app/models/marketplace/listing.rb" => %w[ListingCreated marketplace],
      "brgen/app/models/marketplace/deal.rb" => %w[MarketplaceDealCreated marketplace],
      "brgen/app/models/marketplace/listing_favorite.rb" => %w[MarketplaceListingFavorited marketplace],
      "brgen/app/models/takeaway/restaurant.rb" => %w[TakeawayRestaurantCreated takeaway],
      "brgen/app/models/takeaway/review.rb" => %w[TakeawayReviewCreated takeaway],
      "brgen/app/models/takeaway/favorite_restaurant.rb" => %w[TakeawayRestaurantFavorited takeaway],
      "brgen/app/models/takeaway/menu_item.rb" => %w[TakeawayMenuItemCreated takeaway],
      "brgen/app/models/tv/channel.rb" => %w[TvChannelCreated tv],
      "brgen/app/models/tv/video.rb" => %w[VideoUploaded tv],
      "brgen/app/models/tv/live_stream.rb" => %w[LiveStreamScheduled tv],
      "brgen/app/models/tv/show.rb" => %w[TvShowCreated tv],
      "brgen/app/models/tv/episode.rb" => %w[TvEpisodeCreated tv],
      "brgen/app/models/tv/broadcast.rb" => %w[BroadcastScheduled tv],
      "brgen/app/models/tv/comment.rb" => %w[TvCommentCreated tv],
      "brgen/app/models/tv/stream_chat.rb" => %w[TvStreamChatCreated tv],
      "brgen/app/models/tv/subscription.rb" => %w[TvChannelSubscribed tv],
      "brgen/app/models/tv/video_note.rb" => %w[TvVideoNoteCreated tv],
      "brgen/app/models/tv/view_event.rb" => %w[TvVideoViewed tv],
      "brgen/app/models/dating/profile.rb" => %w[DatingProfileCreated dating],
      "brgen/app/models/dating/dislike.rb" => %w[DatingDislike dating]
    }

    app_record = read_source(File.join(ROOT, "shared/app/models/application_record.rb"))
    assert_includes app_record, "include Shared::ActivityTrackable"

    expected_events.each do |relative, (event_name, vertical)|
      source = read_source(File.join(ROOT, relative))
      assert_includes source, "tracks_activity"
      assert_includes source, event_name
      assert_includes source, "source_vertical: \"#{vertical}\""
    end

    video_source = read_source(File.join(ROOT, "brgen/app/models/tv/video.rb"))
    assert_includes video_source, "VideoPublished"
    assert_includes video_source, "saved_change_to_status?"

    broadcast_source = read_source(File.join(ROOT, "brgen/app/models/tv/broadcast.rb"))
    assert_includes broadcast_source, "BroadcastScheduled"
    assert_includes broadcast_source, "BroadcastStarted"
    assert_includes broadcast_source, "BroadcastEnded"
  end

  def test_marketplace_reviews_and_geo_localized_listings_are_wired
    migration = read_source(File.join(ROOT, "brgen/db/migrate/20260707120000_create_marketplace_reviews_and_geo_listings.rb"))
    listing = read_source(File.join(ROOT, "brgen/app/models/marketplace/listing.rb"))
    review = read_source(File.join(ROOT, "brgen/app/models/marketplace/review.rb"))
    listings_controller = read_source(File.join(ROOT, "brgen/app/controllers/marketplace/listings_controller.rb"))
    reviews_controller = read_source(File.join(ROOT, "brgen/app/controllers/marketplace/reviews_controller.rb"))
    geo_stamp = read_source(File.join(ROOT, "shared/app/services/shared/review_geo_stamp.rb"))
    routes = read_source(File.join(ROOT, "brgen/config/routes.rb"))
    index = read_source(File.join(ROOT, "brgen/app/views/marketplace/listings/index.html.erb"))
    card = read_source(File.join(ROOT, "brgen/app/views/marketplace/listings/_card.html.erb"))
    show = read_source(File.join(ROOT, "brgen/app/views/marketplace/listings/show.html.erb"))

    assert_includes migration, "create_table :marketplace_reviews"
    assert_includes migration, "add_column :marketplace_listings, :latitude"
    assert_includes migration, "add_column :marketplace_listings, :longitude"
    assert_includes migration, "add_column :marketplace_listings, :reviews_count"
    assert_includes listing, "has_many :reviews"
    assert_includes listing, "include Shared::GeoLocatable"
    assert_includes listing, "scope :near"
    assert_includes listing, "reviewable_by?"
    assert_includes listing, "update_rating!"
    assert_includes review, "class Marketplace::Review"
    assert_includes review, "MarketplaceReviewCreated"
    assert_includes review, "buyer_has_completed_interaction"
    assert_includes review, "seller_cannot_review_own_listing"
    assert_includes listings_controller, "@listing_distances"
    assert_includes listings_controller, "Marketplace::Listing.radius_from"
    assert_includes reviews_controller, "Marketplace::ReviewsController"
    # The reviewer's coordinates are still stamped onto the review at create
    # time; the four lines that do it moved to Shared::ReviewGeoStamp, which
    # takeaway's reviews controller calls the same way.
    assert_includes reviews_controller, "Shared::ReviewGeoStamp.apply!"
    assert_includes geo_stamp, "reviewer_lat"
    assert_includes geo_stamp, "reviewer_lng"
    assert_includes routes, "resources :reviews, only: %i[create]"
    assert_includes index, ":radius_km"
    assert_includes card, "marketplace.distance_km"
    assert_includes card, "reviews_count"
    assert_includes show, "listing_reviews_path"
    assert_includes show, "@reviews"
  end

  def test_playlist_import_embed_schema_trending_and_expiry_are_wired
    migration = read_source(File.join(ROOT, "brgen/db/migrate/20260707121000_add_playlist_import_embed_and_expiry_fields.rb"))
    playlist = read_source(File.join(ROOT, "brgen/app/models/playlist/playlist.rb"))
    track = read_source(File.join(ROOT, "brgen/app/models/playlist/track.rb"))
    importer = read_source(File.join(ROOT, "brgen/engines/playlist/app/services/playlist/track_import.rb"))
    imports_controller = read_source(File.join(ROOT, "brgen/app/controllers/playlist/imports_controller.rb"))
    playlists_controller = read_source(File.join(ROOT, "brgen/app/controllers/playlist/playlists_controller.rb"))
    tracks_controller = read_source(File.join(ROOT, "brgen/app/controllers/playlist/tracks_controller.rb"))
    routes = read_source(File.join(ROOT, "brgen/config/routes.rb"))
    schema_helper = read_source(File.join(ROOT, "shared/app/helpers/schema_helper.rb"))
    # _player alone. It used to be read together with a _queue partial, on the
    # stated grounds that the player "renders" it — and it did not. _queue was
    # split out of _player, then _player grew the queue markup back inline and
    # nothing rendered the extracted file again. This assertion passed because
    # the file existed, not because the relationship did. Deleted 2026-08-25.
    player = read_source(File.join(ROOT, "brgen/app/views/playlist/playlists/_player.html.erb"))
    show = read_source(File.join(ROOT, "brgen/app/views/playlist/playlists/show.html.erb"))
    index = read_source(File.join(ROOT, "brgen/app/views/playlist/playlists/index.html.erb"))
    hosted_form = read_source(File.join(ROOT, "brgen/app/views/playlist/hosted_tracks/_form.html.erb"))
    stimulus = read_source(File.join(ROOT, "brgen/app/javascript/controllers/playlist_player_controller.js"))

    assert_includes migration, "add_column :playlist_tracks, :expires_at"
    assert_includes migration, "add_column :playlist_tracks, :privacy"
    assert_includes playlist, "city_trending"
    assert_includes playlist, "duration_seconds"
    assert_includes track, "external_embed_url"
    assert_includes track, "youtube_embed_url"
    assert_includes track, "spotify_embed_url"
    assert_includes track, "w.soundcloud.com/player"
    assert_includes importer, "TrackImport"
    assert_includes importer, "youtube.com"
    assert_includes importer, "spotify.com"
    assert_includes importer, "soundcloud.com"
    assert_includes imports_controller, "require_user_session"
    assert_includes imports_controller, "return if performed?"
    assert_includes playlists_controller, "def embed"
    assert_includes playlists_controller, "Playlist::Track.unexpired"
    assert_includes tracks_controller, ":expires_at"
    assert_includes routes, "member { get :embed }"
    assert_includes routes, "resources :imports, only: :create"
    assert_includes schema_helper, "MusicPlaylist"
    assert_includes schema_helper, "MusicRecording"
    assert_includes schema_helper, "iso8601_duration"
    assert_includes player, 'itemtype="https://schema.org/MusicPlaylist"'
    assert_includes player, "data-playlist-player-embed-param"
    assert_includes player, "playlist-embed-frame"
    assert_includes stimulus, "embedTarget"
    assert_includes show, "json_ld_for(@playlist, type: :music_playlist)"
    assert_includes show, "playlist_imports_path"
    assert_includes show, "embed_playlist_url"
    refute_includes show, "embed_playlist_playlist_url"
    assert_includes hosted_form, "form.datetime_field :expires_at"
  end

  def test_takeaway_geocoding_menu_availability_and_order_state_machine_are_wired
    migration = read_source(File.join(ROOT, "brgen/db/migrate/20260707122000_harden_takeaway_geo_availability_and_orders.rb"))
    restaurant = read_source(File.join(ROOT, "brgen/app/models/takeaway/restaurant.rb"))
    menu_item = read_source(File.join(ROOT, "brgen/app/models/takeaway/menu_item.rb"))
    order = read_source(File.join(ROOT, "brgen/app/models/takeaway/order.rb"))
    order_item = read_source(File.join(ROOT, "brgen/app/models/takeaway/order_item.rb"))
    restaurants_controller = read_source(File.join(ROOT, "brgen/app/controllers/takeaway/restaurants_controller.rb"))
    orders_controller = read_source(File.join(ROOT, "brgen/app/controllers/takeaway/orders_controller.rb"))
    new_view = read_source(File.join(ROOT, "brgen/app/views/takeaway/restaurants/new.html.erb"))
    restaurant_show = read_source(File.join(ROOT, "brgen/app/views/takeaway/restaurants/show.html.erb"))
    order_show = read_source(File.join(ROOT, "brgen/app/views/takeaway/orders/show.html.erb"))

    assert_includes migration, "change_column_default :takeaway_menu_items, :available"
    assert_includes migration, "add_index :takeaway_restaurants, %i[latitude longitude]"
    assert_includes restaurant, 'require "zlib"'
    assert_includes restaurant, "before_validation :geocode_if_needed"
    assert_includes restaurant, "stable_coordinate_offsets"
    assert_includes restaurant, "City.find_by(id: self[:city_id])"
    assert_includes menu_item, "available_for_order?"
    assert_includes menu_item, "self.available = true if available.nil?"
    assert_includes order_item, "menu_item_must_be_available"
    assert_includes order, "TRANSITIONS ="
    assert_includes order, "transition_to!"
    assert_includes order, "status_transition_allowed"
    assert_includes order, "status_in_database"
    assert_includes restaurants_controller, ":latitude"
    assert_includes restaurants_controller, ":longitude"
    assert_includes orders_controller, "menu_items.available.find_by"
    assert_includes orders_controller, "params[:status].presence"
    assert_includes new_view, "f.number_field :latitude"
    assert_includes restaurant_show, "f.check_box :available"
    assert_includes restaurant_show, "item.vegan?"
    assert_includes order_show, "Takeaway::Order::TRANSITIONS.fetch"
  end

  def test_queue_failure_summary_and_digest_schedule
    rows = [
      { class_name: "ExampleJob", queue_name: "bulk", failures: 3, last_failed_at: "2026-01-01 04:00:00" }
    ]
    summary = Shared::QueueFailureSummary.call(rows, app: "brgen")
    assert_includes summary, "ExampleJob (bulk): 3 failure(s)"
    assert_includes summary, "brgen queue dead letters"

    source = read_source(File.join(ROOT, "brgen/config/recurring.yml"))
    assert_includes source, "queue_failure_digest:"
    assert_includes source, "class: QueueFailureDigestJob"
    assert_includes source, "schedule: every day at 5am"

    job_source = read_source(File.join(ROOT, "brgen/app/jobs/queue_failure_digest_job.rb"))
    assert_includes job_source, "solid_queue_failed_executions"
    assert_includes job_source, "QueueFailureMailer.daily_digest"
  end

  def test_cable_health_alert_trips_at_one_thousand_connections
    assert Shared::CableHealth.alert?(connection_count: 1_001, max_connections: 1_000)
    refute Shared::CableHealth.alert?(connection_count: 999, max_connections: 1_000)
    assert_equal "brgen cable at 1001/1000 connections",
                 Shared::CableHealth.message(app: "brgen", connection_count: 1_001, max_connections: 1_000)
  end

  def test_turbo_navigation_and_cache_controls_are_explicit
    hotwire = read_source(File.join(ROOT, "shared/frontend/hotwire.js"))
    assert_includes hotwire, "Turbo.config.drive.progressBarDelay = 100"

    %w[
      amber/app/javascript/application.js
      bsdports/app/javascript/application.js
    ].each do |relative|
      source = read_source(File.join(ROOT, relative))
      assert_includes source, 'import "pub4/hotwire"'
    end

    %w[
      amber/app/views/layouts/application.html.erb
      bsdports/app/views/layouts/application.html.erb
      brgen/app/views/layouts/application.html.erb
    ].each do |relative|
      source = read_source(File.join(ROOT, relative))
      assert_includes source, "data-turbo-permanent"
      refute_includes source, 'turbo-cache-control", content: "no-cache"'

# The sign-out link carries turbo_prefetch: false so a hover-prefetch
# cannot fire the DELETE. Which file holds it is not the point and has
# already moved twice: amber factors it into shared/_sidebar_nav, and on
# 2026-08-26 brgen's went into layouts/_sidebar when the layout was split
# for length. This asserted one hardcoded partial path and went red on
# that move even though the rendered markup was byte-identical — so it
# reads the layout together with every partial the layouts directory and
# shared/ hold, and asks only that the attribute exists somewhere the
# layout can reach.
app_dir = relative.split("/").first
haystack = source + Dir.glob(File.join(ROOT, app_dir, "app/views/{layouts,shared}/_*.erb"))
                       .map { |partial| File.read(partial) }.join
assert_includes haystack, "turbo_prefetch: false",
                "#{app_dir}: the sign-out link must not be hover-prefetchable"
    end

    setup = read_source(File.join(ROOT, "shared/app/controllers/concerns/shared/application_setup.rb"))
    assert_includes setup, "turbo_refreshes_with :morph, scroll: :preserve"

    # There used to be a fourth check here, against
    # shared/frontend/layouts/_nav.html.erb, asserting the same two attributes
    # the loop above already asserts on all three real layouts. shared/frontend
    # is registered as an *asset* path (engine.rb "shared.frontend_assets"),
    # never a view path, so nothing could render that file -- and it still used
    # user_signed_in? and @app_name from before the engine extraction. This
    # assertion was its only reader, so it guarded markup that could not reach a
    # page while reading as coverage. The file and its four siblings are gone.

    pagy_source = read_source(File.join(ROOT, "shared/config/initializers/pagy.rb"))
    assert_includes pagy_source, 'data-turbo-prefetch="false"'
    assert_includes pagy_source, 'rel="prefetch"'
  end

  # This was one 102-line method called
  # test_sqlite_wal_and_shared_stimulus_components_are_present, and its name had
  # stopped describing it: it also held the Stimulus registry, the post card and
  # clipboard wiring, responsive images, three PWA manifests, two service
  # workers, the brgen layout, bsdports HTTP caching and a recurring job. Six
  # unrelated contracts sharing nothing but a `def`.
  #
  # Split at the contract bound, which also fixes what a bundle costs you when it
  # fails: minitest stops at the first failed assertion, so a broken database.yml
  # meant the other five contracts were never checked that run, and the failure
  # named a method whose title mentioned neither.
  def test_sqlite_runs_in_wal_mode_with_strict_loading
    %w[
      amber/config/database.yml
      brgen/config/database.yml
      bsdports/config/database.yml
    ].each do |relative|
      source = read_source(File.join(ROOT, relative))
      assert_includes source, "journal_mode: WAL"
    end

    source = read_source(File.join(ROOT, "shared/config/environments/development.rb"))
    assert_includes source, "strict_loading_by_default = true"
  end

  def test_shared_stimulus_components_are_registered
    source = read_source(File.join(ROOT, "shared/frontend/stimulus_boot.js"))
    %w[
      Clipboard
      Dropdown
      Hotkey
      Notification
      Reveal
      Sortable
      toast
      TextareaAutogrow
      PasswordVisibility
      RailsNestedForm
      CharacterCounter
      CheckboxSelectAll
      ReadMore
    ].each do |component|
      assert_includes source, component
    end

    # carousel is registered on demand, not statically imported: its dependency
    # is swiper (cdn.jsdelivr.net), and importing it here put that host on the
    # first-paint critical path of every page in all three apps. Assert the lazy
    # registration by name.
    assert_includes source, "LAZY_COMPONENTS"
    %w[carousel].each do |name|
      assert_match(/\["#{name}",\s*\(\)\s*=>\s*import\(/, source,
                   "#{name} should be lazily imported, not statically")
    end

    # timeago was the other lazy component until 2026-08-12. It read
    # data-timeago-datetime-value, which no view ever set, so its only possible
    # effect was to replace localised Norwegian with date-fns English. Gone with
    # its pin, its vendored file and the unpkg.com host it needed. Matched on
    # the registration form, not the bare word: the comment above LAZY_COMPONENTS
    # explains the removal and has to keep naming it.
    refute_match(/\["timeago",/, source, "timeago has no consumer in any app")

    # Dialog, ScrollTo, Sound and SpeechRecognition were imported, registered,
    # pinned and vendored with no data-controller for them in any of the four
    # apps. Kept out.
    %w[Dialog ScrollTo Sound SpeechRecognition].each do |dead|
      refute_includes source, dead, "#{dead} has no consumer in any app"
    end
  end

  def test_shared_components_are_wired_into_the_views_that_use_them
    assert_includes read_source(File.join(ROOT, "shared/app/views/shared/_toast.html.erb")), 'data-controller="toast"'
    assert_includes read_source(File.join(ROOT, "shared/frontend/examples.html.erb")), 'data-controller="toast"'

    wardrobe_form = read_source(File.join(ROOT, "amber/app/views/wardrobe_items/_form.html.erb"))
    assert wardrobe_form.include?("textarea-autogrow") || wardrobe_form.include?("character-counter")
    assert_includes read_source(File.join(ROOT, "shared/app/views/comments/_form_fields.html.erb")), "textarea-autogrow"
    # What matters here is that the post partial is fragment-cached at all. The
    # exact key was pinned as a literal, which froze an implementation detail:
    # keying on Current.user&.id meant a per-guest key, and brgen mints a fresh
    # guest for every cookieless request, so the cache scored zero hits on
    # crawler traffic. Assert the caching, not the key it happens to use.
    assert_includes read_source(File.join(ROOT, "brgen/app/views/posts/_post.html.erb")), "cache [post"
    assert_includes read_source(File.join(ROOT, "amber/app/views/posts/_post.html.erb")), "cache [post"
    # The share button uses the shared clipboard component. This pinned the
    # literal PAIR "clipboard popover", which is the same frozen-detail mistake
    # the comment above records for the cache key, six lines up in this test:
    # the popover was a tooltip duplicating the button's own aria-label, it
    # could not fire on a touch viewport at all, and removing it from all four
    # buttons cost 100 of the page's 270 controller instances. Assert the
    # component that does the work, not the company it keeps.
    post_partial = read_source(File.join(ROOT, "brgen/app/views/posts/_post.html.erb"))
    assert_includes post_partial, 'data-controller="clipboard"'
    # ERB comments stripped before the refutation. This fired on 2026-08-10
    # against a partial containing no popover at all: the comment recording *why*
    # the popover was removed says the word, and a refute_includes over raw source
    # cannot tell markup from the note explaining its absence. Third time that
    # shape bit in one session -- see front_page_weight_test.rb.
    refute_includes post_partial.gsub(/<%#.*?%>/m, ""), "popover",
                    "popover was removed as dead weight -- do not reintroduce it as a tooltip"
    assert_includes read_source(File.join(ROOT, "brgen/app/views/posts/_post.html.erb")), "shared/post_card"
    assert_includes read_source(File.join(ROOT, "amber/app/views/posts/_post.html.erb")), "shared/post_card"
    assert_includes read_source(File.join(ROOT, "shared/app/views/shared/_post_card.html.erb")), "shared/feed_card"
    assert_includes read_source(File.join(ROOT, "shared/app/views/shared/_copyable.html.erb")),
                    'data-controller="clipboard"'
  end

  def test_responsive_images_are_served_as_lazy_webp_pictures
    helper_source = read_source(File.join(ROOT, "amber/app/helpers/application_helper.rb"))
    assert_includes helper_source, "responsive_image_url"
    assert_includes helper_source, 'loading: "lazy"'
    # The <picture> itself is Shared::UiHelper#responsive_picture_tag, which
    # brgen and amber both call and bsdports could — amber keeps only its
    # named-variant preset branch and the url_for strategy it hands over.
    assert_includes helper_source, "responsive_picture_tag("
    picture_source = read_source(File.join(ROOT, "shared/app/helpers/shared/ui_helper.rb"))
    assert_includes picture_source, "content_tag(:picture)"
    assert_includes picture_source, 'type: "image/webp"'
    assert_includes read_source(File.join(ROOT, "amber/app/views/items/show.html.erb")), "responsive_image_tag photo"
    # The dressing room composition moved into a partial when the guest landing
    # page started rendering the same mannequin.
    assert_includes read_source(File.join(ROOT, "amber/app/views/shared/_dressing_room.html.erb")),
                    "responsive_image_url(item.photos.first"
  end

  def test_pwa_manifests_and_service_workers_are_installable
    %w[
      brgen/app/views/pwa/manifest.json.erb
      amber/app/views/pwa/manifest.json.erb
      bsdports/app/views/pwa/manifest.json.erb
    ].each do |relative|
      source = read_source(File.join(ROOT, relative))
      assert_includes source, '"shortcuts"'
    end

    brgen_manifest = read_source(File.join(ROOT, "brgen/app/views/pwa/manifest.json.erb"))
    assert_match(/pwa\.new_listing|New listing/, brgen_manifest)
    assert_includes brgen_manifest, "protocol_handlers"
    assert_includes brgen_manifest, "web+brgen"
    # Same-origin shortcuts only (cross-subdomain urls break Chrome scope checks)
    assert_includes brgen_manifest, 'when "playlist"'
    assert_includes brgen_manifest, "/playlists/new"
    refute_includes brgen_manifest, "brgen_ai_url"
    refute_includes brgen_manifest, "//dating."
    assert_includes read_source(File.join(ROOT, "brgen/app/javascript/controllers/push_controller.js")),
                    "navigator.setAppBadge"
    assert_includes read_source(File.join(ROOT, "brgen/app/javascript/controllers/push_controller.js")),
                    "navigator.clearAppBadge"
    assert_includes read_source(File.join(ROOT, "shared/pwa/service_worker.js")), "setAppBadge"
    brgen_sw = read_source(File.join(ROOT, "brgen/app/views/pwa/service-worker.js"))
    # Back on the shared Workbox worker as of 2026-08-14. It left because the
    # precache manifest froze fingerprinted asset URLs that 404'd at the next
    # deploy; build_workbox now ignores assets/**, so the manifest carries only
    # stable URLs and brgen regains the offline form queue and periodic sync.
    # What is asserted is the property that matters, not which builder produced
    # it: an offline fallback, and no digested URL pinned in the precache.
    assert_includes brgen_sw, "/offline"
    assert_includes brgen_sw, "offline-forms"
    assert_empty brgen_sw.scan(%r{/assets/[^"']*-[0-9a-f]{8,}\.(?:js|css)}).uniq, "precache pins a digested URL"
    # The layout and the chrome it renders, read as one surface. brgen_ai_url is
    # reached from the mobile sheet, which moved into shared/_mobile_chrome when
    # the layout was split at its length ceiling — the link did not move, the
    # file boundary did, and an assertion naming one file called that a
    # regression.
    brgen_layout = %w[layouts/application shared/_mobile_chrome].sum("") { |v| read_source(File.join(ROOT, "brgen/app/views/#{v}.html.erb")) }
    assert_includes brgen_layout, "data-push-unread-value="
    # The sheet that links out to the AI surface is shared/_mobile_chrome, which
    # the layout renders. The invariant is that the shell reaches it, not which
    # of the two files spells the helper.
    %w[ai_nav_link mobile_chrome].each { |p| assert_includes brgen_layout, %(render "shared/#{p}") }
    assert_includes read_source(File.join(ROOT, "brgen/app/views/shared/_mobile_chrome.html.erb")), "brgen_ai_url"
    refute_match(/javascript_include_tag "(face|particle_kernel)"/, brgen_layout)
    assert_match(/pwa\.create_outfit|Create outfit/, read_source(File.join(ROOT, "amber/app/views/pwa/manifest.json.erb")))
    assert_match(/pwa\.search_ports|Search ports/, read_source(File.join(ROOT, "bsdports/app/views/pwa/manifest.json.erb")))
    assert_includes read_source(File.join(ROOT, "amber/app/views/pwa/manifest.json.erb")), '"file_handlers"'
    assert_includes read_source(File.join(ROOT, "amber/app/views/pwa/manifest.json.erb")), "image/*"
  end

  def test_bsdports_caches_publicly_and_brgen_checks_cable_health
    ports_controller = read_source(File.join(ROOT, "bsdports/app/controllers/ports_controller.rb"))
    assert_includes ports_controller, "expires_in 10.minutes, public: true"
    assert_includes ports_controller, "fresh_when(@port, public: true)"

    source = read_source(File.join(ROOT, "brgen/config/recurring.yml"))
    assert_includes source, "cable_health_check:"
    assert_includes source, "class: CableHealthJob"
    assert_includes source, "schedule: every hour at minute 7"
  end

  def test_brgen_users_maps_checkins_and_listening_parties_are_wired
    routes = read_source(File.join(ROOT, "brgen/config/routes.rb"))
    migration = read_source(File.join(ROOT, "brgen/db/migrate/20260708120000_create_maps_check_ins_and_listening_parties.rb"))

    assert_includes routes, "resources :users, only: %i[show new create edit update]"
    assert_includes routes, "post :check_in"
    assert_includes routes, "resource :listening_party"
    assert_includes migration, "create_table :place_check_ins"
    assert_includes migration, "create_table :playlist_listening_parties"
    assert_includes migration, "idx_party_messages_on_party_and_created_at"
    assert_includes read_brgen("app/controllers/users_controller.rb"), "def show"
    assert_includes read_brgen("app/controllers/maps/places_controller.rb"), "def check_in"
    assert_includes read_brgen("app/controllers/playlist/listening_parties_controller.rb"), "def create"
    assert_includes read_brgen("app/views/users/show.html.erb"), "follow_button"
    assert_includes read_brgen("engines/maps/app/views/maps/places/show.html.erb"), "check_in_place_path"
    assert_includes read_brgen("app/views/playlist/sets/show.html.erb"), "set_listening_party_path"
  end

  def test_bsdports_security_advisory_refresh_job_uses_nvd_service
    job = read_source(File.join(ROOT, "bsdports/app/jobs/security_advisory_refresh_job.rb"))
    recurring = read_source(File.join(ROOT, "bsdports/config/recurring.yml"))

    assert_includes job, "NvdCve.crossref"
    assert_includes job, "CURSOR_KEY"
    assert_includes recurring, "SecurityAdvisoryRefreshJob"
  end

  def test_shared_auth_fields_migrated_across_rails_apps
    %w[amber brgen bsdports].each do |app|
      migration = File.join(ROOT, app, "db/migrate/20260709120000_add_shared_auth_fields_to_users.rb")
      assert File.file?(migration), "missing shared auth migration for #{app}"

      source = File.read(migration)
      assert_includes source, ":remember_token"
      assert_includes source, ":magic_link_token"
      assert_includes source, ":two_factor_enabled"
    end

    initializer = read_source(File.join(ROOT, "shared/config/initializers/auth_extensions.rb"))
    assert_includes initializer, "Shared::UserAuthExtensions"
    assert_includes read_source(File.join(ROOT, "shared/app/models/concerns/shared/user_auth_extensions.rb")),
                    "ensure_auth_column!"
  end

  def test_playlist_tracks_schema_includes_user_ownership
    schema = read_source(File.join(ROOT, "brgen/db/schema.rb"))
    assert_includes schema, 'create_table "playlist_tracks"'
    assert_includes schema, 't.integer "user_id"', "brgen schema missing playlist_tracks.user_id"
    assert_includes schema, "index_playlist_tracks_on_user_id"
    assert_includes schema, 'add_foreign_key "playlist_tracks", "users"'
  end

  def test_schema_dumps_include_shared_auth_user_columns
    %w[amber brgen bsdports].each do |app|
      schema = read_source(File.join(ROOT, app, "db", "schema.rb"))
      assert_includes schema, 't.string "remember_token"', "#{app} schema missing remember_token"
      assert_includes schema, 't.string "magic_link_token"', "#{app} schema missing magic_link_token"
      assert_includes schema, 't.boolean "two_factor_enabled"', "#{app} schema missing two_factor_enabled"
      assert_includes schema, "index_users_on_remember_token", "#{app} schema missing remember_token index"
    end
  end

  def test_messenger_subdomain_routes_conversations_and_messages
    routes = read_source(File.join(ROOT, "brgen/config/routes.rb"))
    assert_includes routes, "constraints(subdomain: MESSENGER_SUBDOMAINS)"
    assert_includes routes, "as: :messenger_root"
    assert_includes routes, "resources :conversations, only: %i[show update create]"
    assert_includes routes, "resources :messages, only: %i[create]"
  end


  def test_playlist_tracks_and_hosted_tracks_wire_user_ownership
    migration = read_brgen("db/migrate/20260709120100_add_user_to_playlist_tracks.rb")
    track = read_brgen("app/models/playlist/track.rb")
    hosted = read_brgen("app/controllers/playlist/hosted_tracks_controller.rb")
    tracks_controller = read_brgen("app/controllers/playlist/tracks_controller.rb")

    assert_includes migration, "add_reference :playlist_tracks, :user"
    assert_includes track, "belongs_to :user"
    assert_includes hosted, "@track.user = Current.user"
    assert_includes tracks_controller, "user: Current.user"
  end



# maps engine wiring: RAILS/test/maps_engine_wiring_contract_test.rb.
# The marketplace scope stays here; it is not a maps fact.
def test_casual_listings_have_a_scope
  assert_includes read_brgen("engines/marketplace/app/models/marketplace/listing.rb"), "scope :casual"
end

  # The username field is gone. It asked you to type the exact handle of the
  # person you wanted, which is the one thing you do not know about somebody you
  # have just met — so the feature worked only for people you had already written
  # to. conversations#new is a people picker, and every row carries the button.
  #
  # The controller half is unchanged and still asserted: create still resolves a
  # partner from params[:username] or params[:user_id], because the picker's
  # button and the profile's Message button both post to it.
  def test_messenger_compose_flow_reaches_the_people_picker
    index = read_brgen("app/views/conversations/index.html.erb")
    rail = read_brgen("app/views/conversations/_rooms_rail.html.erb")
    results = read_brgen("app/views/conversations/_people_results.html.erb")
    controller = read_brgen("app/controllers/conversations_controller.rb")

    assert_includes index, "messenger-window"
    assert_includes rail, "new_conversation_path"
    assert_includes results, "user_conversations_path(person)"
    assert_includes controller, "def new"
    assert_includes controller, "User.messageable"
    assert_includes controller, "resolve_conversation_partner"
    assert_includes controller, "params[:username]"
  end

  def test_sitemap_routes_and_shared_builder_across_rails_apps
    sentinel = read_source(File.join(ROOT, "shared/app/views/shared/_infinite_scroll_sentinel.html.erb"))
    builder = read_source(File.join(ROOT, "shared/app/services/shared/sitemap_builder.rb"))

    assert_includes sentinel, "data-cuisine"
    assert_includes sentinel, "data-kind"
    assert_includes builder, "Builder::XmlMarkup"

    %w[amber brgen bsdports].each do |app|
      routes = read_source(File.join(ROOT, "#{app}/config/routes.rb"))
      assert_includes routes, "sitemaps#index", "#{app} missing sitemap route"
      assert File.file?(File.join(ROOT, app, "app/controllers/sitemaps_controller.rb")),
             "#{app} missing SitemapsController"
      source = read_source(File.join(ROOT, app, "app/controllers/sitemaps_controller.rb"))
      assert_includes source, "Shared::Sitemapable"
      assert_includes source, "sitemap_entries"
    end

    assert_includes read_source(File.join(ROOT, "brgen/config/routes.rb")), "robots#show"
    # City scoping and per-model coverage: RAILS/test/sitemap_city_scope_contract_test.rb.
    assert_includes read_brgen("app/controllers/sitemaps_controller.rb"), "Brgen::DomainRegistry.resolve"
  end



  def test_playlist_set_likes_controller_and_ui_are_wired
    controller = read_brgen("app/controllers/playlist/likes_controller.rb")
    show = read_brgen("app/views/playlist/sets/show.html.erb")

    assert_includes controller, "class Playlist::LikesController"
    refute_includes controller, "module Playlist"
    assert_includes controller, "find_or_create_by!"
    assert_includes controller, "destroy_all"
    assert_includes show, "set_like_path" # engine-internal helper (unprefixed inside Playlist::Engine)
    assert_includes show, "likes.count"
  end


  def test_marketplace_stores_edit_update_destroy_are_wired
    controller = read_brgen("app/controllers/marketplace/stores_controller.rb")

    assert_includes controller, "def edit"
    assert_includes controller, "def update"
    assert_includes controller, "def destroy"
    assert_includes controller, "authorize_owner"
    assert [ File.join(ROOT, "brgen/app/views/marketplace/stores/edit.html.erb"),
            File.join(ROOT, "brgen/engines/marketplace/app/views/marketplace/stores/edit.html.erb") ].any? { |p| File.file?(p) }
    assert_includes read_brgen("app/assets/stylesheets/_marketplace_stores.scss"), ".store-grid"
    assert_includes read_brgen("app/assets/stylesheets/application.scss"), "_marketplace_stores"
  end



  def test_brgen_visual_polish_stack_is_wired
    layout = read_brgen("app/views/layouts/application.html.erb")
    scss = read_brgen("app/assets/stylesheets/application.scss")
    manifest = read_brgen("app/views/pwa/manifest.json.erb")
    show = read_brgen("app/views/posts/show.html.erb")
    app_js = read_brgen("app/javascript/application.js")

    # Guest splash removed — home lands on feed without modal overlay
    refute_includes layout, "yield :splash"
    refute_includes layout, 'id="splash"'
    assert_includes layout, "#000000"
    assert_includes manifest, '"theme_color": "#000000"'
    assert_includes scss, "_card_modifiers"
    assert_includes scss, "_chrome_polish"
    assert_includes scss, "offline_page"
    assert_includes read_brgen("app/assets/stylesheets/_vertical_playlist.scss"), ".playlist-top"
    assert_includes read_brgen("app/assets/stylesheets/_vertical_tv_cards.scss"), ".tv-live-streams"
    assert_includes show, "feed-post-show"
    assert_includes show, "feed_icon"
    refute_includes show, "post_show"
    refute_includes app_js, "brgen_shell"
    refute_includes read_brgen("config/importmap.rb"), "brgen_shell"
    assert_includes read_source(File.join(ROOT, "shared/frontend/stimulus_boot.js")), "pub4/brgen_shell"
    assert_includes read_source(File.join(ROOT, "shared/config/importmap_baseline.rb")), "pub4/brgen_shell"
    # The token is declared, not what it is set to. design_tokens.yml
    # system.radius_card is the authority for the value, and pinning the pixels
    # here made this a second copy of it: the ladder moved to 12px and this
    # assertion failed on a change that was correct everywhere else.
    assert_includes read_source(File.join(ROOT, "shared/app/assets/stylesheets/_dialect_tokens.scss")), "--radius-card:"
    refute File.exist?(File.join(ROOT, "brgen/app/controllers/playlist_controller.rb"))
    refute File.exist?(File.join(ROOT, "brgen/app/views/shared/_vote.html.erb"))
    assert_includes read_source(File.join(ROOT, "_deploy.sh")), "DEMO_SEED_ON_DEPLOY"
    assert_includes read_source(File.join(ROOT, "shared/config/initializers/omniauth.rb")), ":snapchat"
    refute_includes read_brgen("app/assets/stylesheets/_posts.scss"), ".post_show"
    assert_includes read_brgen("app/assets/stylesheets/_nav.scss"), "border-bottom-color: var(--accent)"
    assert_includes read_brgen("app/views/layouts/application.html.erb"), "unless vertical_surface?"
  end

  def test_demo_seed_media_uses_shared_postpro_pipeline
    assert_includes read_source(File.join(ROOT, "shared/app/services/shared/demo_media.rb")), "attach_remote_postpro!"
    assert_includes read_source(File.join(ROOT, "shared/app/services/shared/postpro_processor.rb")), "PostproProcessor"
    assert_includes read_brgen("lib/brgen/bergen_demo_seeder.rb"), "attach_remote_postpro!"
    assert_includes read_brgen("lib/brgen/bergen_demo_seeder.rb"), "seed_places"
    assert_includes read_brgen("lib/brgen/bergen_demo_seeder.rb"), "seed_takeaway"
    assert_includes read_brgen("lib/brgen/bergen_demo_seeder.rb"), "seed_tv"
    assert File.exist?(File.join(ROOT, "brgen/config/demo_media/bergen.yml")), "bergen demo media catalog"
    assert_includes read_source(File.join(ROOT, "amber/lib/amber/amber_demo_seeder.rb")), "attach_remote_postpro!"
    assert_includes read_source(File.join(ROOT, "amber/app/jobs/wardrobe_media_job.rb")), "PostproProcessor.apply_to_record!"
  end

  def test_brgen_views_have_valid_page_header_open_tags
    offenders = Dir[File.join(ROOT, "brgen/app/views/**/*.html.erb")].select do |path|
      File.read(path).match?(/^(div|header) class="page-header"/m)
    end
    assert_empty offenders, "broken page-header open tags (missing '<'): #{offenders.map { |p| p.sub(%r{.*brgen/}, '') }.join(', ')}"
  end

  private
end
