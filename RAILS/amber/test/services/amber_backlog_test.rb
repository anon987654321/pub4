# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class AmberBacklogTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def read(relative)
    File.read(File.join(ROOT, relative))
  end

  # These pages render through I18n now, so a literal English string in the
  # template stopped being there the moment the page was localised — the
  # assertion failed on a view that had got better, not worse. Pin the key in
  # the template and the copy in en.yml instead: the page still has to say this
  # sentence, and the check survives the next locale. Same reasoning as
  # b369c6213 for brgen's rendered-body tests.
  def assert_localised(relative, key, english)
    assert_includes read(relative), %(t("#{key}"))
    assert_equal english, locale_value(:en, key), "en.yml #{key} drifted from the copy #{relative} promises"
  end

  # Read the YAML rather than asking I18n.
  #
  # Two assertions here used `I18n.t(key, locale: :en)` and were order-dependent
  # because of it: they passed in a full-suite run, where some earlier test had
  # already forced the :en translations to load, and failed on their own with
  # "Translation missing: en.wardrobe.life_phases" for a key that is present in
  # en.yml. A file this test already reads cannot be warmed up wrong.
  def locale_value(locale, key)
    root = YAML.safe_load_file(File.join(ROOT, "config", "locales", "#{locale}.yml")).fetch(locale.to_s)
    key.split(".").reduce(root) { |node, segment| node.fetch(segment) }
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
    assert_includes read("app/views/connections/index.html.erb"), "connections.title"
    assert_localised "app/views/live_streams/index.html.erb", "live_streams.title", "Style sessions"
    # Was assert_includes … "Message sent", which is the same coupling the helper
    # above exists to remove: the flash went through I18n on 2026-08-11 and the
    # assertion failed on a controller that had got better.
    assert_localised "app/controllers/messages_controller.rb", "flash.message_sent", "Message sent."
    # "New message" was the compose form's heading before the page was
    # localised; the form is what the assertion was about, and it does
    # not move when the copy does.
    assert_includes read("app/views/messages/index.html.erb"), 'render "messages/form"'
    assert_localised "app/views/messages/index.html.erb", "messages.title", "Messages"
    assert_localised "app/views/connections/index.html.erb", "connections.title", "Connections"
  end

  def test_wardrobe_analytics_upload_pipeline_and_outfit_generation_are_wired
    analytics = read("app/services/wardrobe_analytics.rb")
    generator = read("app/services/outfit_generation.rb")
    routes = read("config/routes.rb")
    item_form = read("app/views/items/_form.html.erb")
    media_picker = File.read(File.join(ROOT, "..", "shared", "frontend", "media_picker_controller.js"))

    assert_includes analytics, "never_worn"
    assert_includes analytics, "underused"
    assert_includes analytics, "tips"
    assert_includes analytics, "rules"
    assert_includes generator, "generate!"
    assert_includes generator, "weather"
    assert_includes generator, "underused?"
    assert_includes routes, "get :analytics"
    assert_includes routes, "post :generate"
    assert_includes read("app/controllers/wardrobe_items_controller.rb"), "WardrobeAnalytics"
    assert_includes read("app/controllers/outfits_controller.rb"), "OutfitGeneration"
    assert_includes read("app/controllers/outfits_controller.rb"), "Weather"
    media_job = read("app/jobs/wardrobe_media_job.rb")
    assert_includes media_job, "FingerprintGarmentJob"
    assert_includes media_job, "photo_polish"
    assert_includes item_form, "media-picker"
    assert_includes item_form, "data-controller="
    assert_includes item_form, "direct_upload: true"
    assert_includes media_picker, "drop(event)"
    assert_localised "app/views/wardrobe_items/analytics.html.erb", "pages.analytics", "Wardrobe analytics"
    assert_localised "app/views/wardrobe_items/analytics.html.erb", "wardrobe.coach_rules", "rules, not AI"
    # assert_localised, like the two lines above it. This read the source for the
    # literal "Generate outfit" and broke when the view became
    # t("outfits.generate_label") — the same shape as the other two, just missed
    # when they were converted. The helper checks both halves: the view goes
    # through the key, and en.yml still says what this test says it says.
    assert_localised "app/views/outfits/index.html.erb", "outfits.generate_label", "Generate outfit"
  end

  def test_style_evolution_timeline_is_wired
    service = read("app/services/style_evolution.rb")
    controller = read("app/controllers/wardrobe_items_controller.rb")
    routes = read("config/routes.rb")
    view = read("app/views/wardrobe_items/timeline.html.erb")

    assert_includes service, "phase_groups"
    assert_includes service, "wear_timeline"
    assert_includes controller, "StyleEvolution"
    assert_includes controller, "def timeline"
    assert_includes routes, "get :timeline"
    # Both through the locale rather than as literals, for the same reason as
    # items.sparks_joy above: asserting English in a default_locale: nb app is
    # what kept the hardcoded copy in the view.
    assert_includes view, "wardrobe.evolution_header"
    assert_includes view, "wardrobe.life_phases"
    assert_equal "Life phases", locale_value(:en, "wardrobe.life_phases")
    assert_equal "Livsfaser", locale_value(:nb, "wardrobe.life_phases")
    assert_includes read("app/views/wardrobe_items/analytics.html.erb"), "timeline_wardrobe_items_path"
  end

  def test_wardrobe_items_migration_and_intelligence_jobs_are_wired
    migration = read("db/migrate/20260708120000_create_wardrobe_items_and_wire_intelligence_jobs.rb")
    media_job = read("app/jobs/wardrobe_media_job.rb")
    ai = read("app/controllers/ai_controller.rb")

    assert_includes migration, "create_table :wardrobe_items"
    assert_includes media_job, "enqueue_once(FingerprintGarmentJob"
    assert_includes media_job, "enqueue_once(CalculateSustainabilityJob"
    assert_includes media_job, "MediaProcessingJob.perform_now"
    assert_includes media_job, "Item::PHOTO_VARIANTS"
    assert_includes ai, "packing_list_items.find_or_create_by!"
    assert_includes read("app/services/wardrobe_ai.rb"), "def fingerprint_for"
    assert_includes read("app/services/wardrobe_ai.rb"), "def self.configured?"
  end

  def test_wardrobe_list_paths_use_named_variants_and_display_preloads
    item = read("app/models/item.rb")
    helper = read("app/helpers/application_helper.rb")
    items_controller = read("app/controllers/items_controller.rb")
    items_reflex = read("app/reflexes/items_infinite_scroll_reflex.rb")
    item_partial = read("app/views/items/_item.html.erb")

    assert_includes item, "PHOTO_VARIANTS"
    assert_includes item, "with_photos_for_display"
    assert_includes item, "attachable.variant"
    assert_includes helper, "IMAGE_PRESETS"
    assert_includes helper, "named_responsive_image_tag"
    assert_includes items_controller, "with_photos_for_display"
    assert_includes items_reflex, "with_photos_for_display"
    assert_includes item_partial, "preset: :card"
    refute_includes item_partial, "widths:"
  end

  def test_konmari_and_honesty_paths_are_wired
    routes = read("config/routes.rb")
    assert_includes routes, "post :clear_joy"
    assert_includes routes, "create_last_chance_outfit"
    assert_includes routes, "affiliate_links"
    assert_includes read("app/jobs/declutter_hygiene_job.rb"), "BOX_DAYS"
    assert_includes read("app/controllers/declutter_controller.rb"), "create_last_chance_outfit"
    # The KonMari badge, asserted through the locale rather than as a literal.
    # This read `assert_includes … "Sparks joy"`, which pinned English into a
    # default_locale: nb app -- and items.sparks_joy already existed, with a
    # Norwegian value, bypassed by the hardcoded string in the view.
    assert_includes read("app/views/items/show.html.erb"), "items.sparks_joy"
    assert_equal "Sparks joy", locale_value(:en, "items.sparks_joy")
    assert_equal "Gir glede", locale_value(:nb, "items.sparks_joy")
    assert_includes read("config/recurring.yml"), "DeclutterHygieneJob"
    assert_includes read("HEIR.md"), "heir"
  end

  def test_creator_profiles_are_wired
    routes = read("config/routes.rb")
    controller = read("app/controllers/creator_profiles_controller.rb")

    assert_includes routes, 'get "creators/:handle"'
    assert_includes routes, "resource :creator_profile"
    assert_includes controller, "def show"
    assert_includes controller, "def create"
    assert_includes read("app/controllers/creator_wardrobe_items_controller.rb"), "def create"
# Through the key, not the rendered word. This asserted the English literal
# "Showcase" and so pinned it in place: the 2026-08-25 i18n pass turned it
# into t("creator.showcase") and this went red for the surface being
# translated. Same shape as the logo contract test, which carries the same
# note about the same week. What the backlog cares about is that the
# showcase section exists, and a key proves that as well as a word does.
assert_includes read("app/views/creator_profiles/show.html.erb"), %q{t("creator.showcase")}
    assert_includes read("app/views/users/show.html.erb"), "new_my_creator_profile_path"
  end
end
