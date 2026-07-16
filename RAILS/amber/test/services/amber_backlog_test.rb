# frozen_string_literal: true

require "minitest/autorun"

class AmberBacklogTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(relative)
    File.read(File.join(ROOT, relative))
  end

  def test_social_live_message_models_are_persisted_and_routed
    migration = read("db/migrate/20260707130000_wire_social_live_messages_and_wardrobe_intelligence.rb")
    user = read("app/models/user.rb")
    routes = read("config/routes.rb")

    assert_includes migration, "create_table :connections"
    assert_includes migration, "create_table :live_streams"
    assert_includes migration, "create_table :messages"
    assert_includes read("app/models/connection.rb"), "STATUSES = %w[pending accepted blocked]"
    assert_includes read("app/models/live_stream.rb"), "def start!"
    assert_includes read("app/models/message.rb"), "scope :unread"
    assert_includes user, "connections_requested"
    assert_includes user, "live_streams"
    assert_includes user, "sent_messages"
    assert_includes routes, "resources :connections"
    assert_includes routes, "resources :live_streams"
    assert_includes routes, "resources :messages"
    assert_includes read("app/views/connections/index.html.erb"), "Connection"
    assert_includes read("app/views/live_streams/index.html.erb"), "Live wardrobe sessions"
    assert_includes read("app/controllers/messages_controller.rb"), "Message sent"
    assert_includes read("app/views/messages/index.html.erb"), "New message"
  end

  def test_wardrobe_analytics_upload_pipeline_and_outfit_generation_are_wired
    migration = read("db/migrate/20260707130000_wire_social_live_messages_and_wardrobe_intelligence.rb")
    analytics = read("app/services/wardrobe_analytics_service.rb")
    generator = read("app/services/outfit_generation_service.rb")
    routes = read("config/routes.rb")
    item_form = read("app/views/items/_form.html.erb")
    media_picker = File.read(File.join(ROOT, "..", "shared", "frontend", "media_picker_controller.js"))

    assert_includes migration, "analysis_status"
    assert_includes analytics, "never_worn"
    assert_includes analytics, "underused"
    assert_includes analytics, "tips"
    assert_includes generator, "generate!"
    assert_includes generator, "weather"
    assert_includes generator, "underused?"
    assert_includes routes, "get :analytics"
    assert_includes routes, "post :generate"
    assert_includes read("app/controllers/wardrobe_items_controller.rb"), "WardrobeAnalyticsService"
    assert_includes read("app/controllers/outfits_controller.rb"), "OutfitGenerationService"
    assert_includes read("app/jobs/wardrobe_media_job.rb"), "enqueue_once(SegmentGarmentImageJob"
    assert_includes read("app/jobs/wardrobe_media_job.rb"), "enqueue_once(RemoveBackgroundJob"
    assert_includes item_form, "media-picker"
    assert_includes item_form, "data-controller="
    assert_includes item_form, "direct_upload: true"
    assert_includes media_picker, "drop(event)"
    assert_includes read("app/views/wardrobe_items/analytics.html.erb"), "Wardrobe analytics"
    assert_includes read("app/views/outfits/index.html.erb"), "Generate outfit"
  end

  def test_style_evolution_timeline_is_wired
    service = read("app/services/style_evolution_service.rb")
    controller = read("app/controllers/wardrobe_items_controller.rb")
    routes = read("config/routes.rb")
    view = read("app/views/wardrobe_items/timeline.html.erb")

    assert_includes service, "phase_groups"
    assert_includes service, "wear_timeline"
    assert_includes controller, "StyleEvolutionService"
    assert_includes controller, "def timeline"
    assert_includes routes, "get :timeline"
    assert_includes view, "Style evolution"
    assert_includes view, "Life phases"
    assert_includes read("app/views/wardrobe_items/analytics.html.erb"), "timeline_wardrobe_items_path"
  end

  def test_wardrobe_items_migration_and_intelligence_jobs_are_wired
    migration = read("db/migrate/20260708120000_create_wardrobe_items_and_wire_intelligence_jobs.rb")
    media_job = read("app/jobs/wardrobe_media_job.rb")
    ai = read("app/controllers/ai_controller.rb")

    assert_includes migration, "create_table :wardrobe_items"
    assert_includes media_job, "enqueue_once(EmbedGarmentJob"
    assert_includes media_job, "enqueue_once(CalculateSustainabilityJob"
    assert_includes media_job, "MediaProcessingJob.perform_now"
    assert_includes ai, "RecommendOutfitsJob.perform_later"
    assert_includes ai, "packing_list_items.find_or_create_by!"
  end

  def test_creator_profiles_are_wired
    routes = read("config/routes.rb")
    controller = read("app/controllers/creator_profiles_controller.rb")

    assert_includes routes, 'get "creators/:handle"'
    assert_includes routes, "resource :creator_profile"
    assert_includes controller, "def show"
    assert_includes controller, "def create"
    assert_includes read("app/controllers/creator_wardrobe_items_controller.rb"), "def create"
    assert_includes read("app/views/creator_profiles/show.html.erb"), "Showcase"
    assert_includes read("app/views/users/show.html.erb"), "new_my_creator_profile_path"
  end
end
