# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/scss"
require_relative "support/critique_sources"

class CritiqueImplementationAmberTest < Minitest::Test
  include CritiqueSources

  def test_amber_product_detail_uses_photo_first_editorial_geometry
    show = read("amber/app/views/items/show.html.erb")
    css = amber_css_source

    assert_includes show, 'class="item-detail-layout"'
    assert_includes show, 'class="item-detail-photos"'
    assert_includes show, 'class="item-detail-facts"'
    assert_includes css, ".item-detail--wardrobe .item-detail-layout"
    assert_includes css, ".item-detail--wardrobe .item-detail-facts"
  end
  def test_amber_flash_uses_shared_semantic_signal
    flash = read("amber/app/views/shared/_flash.html.erb")
    signal = read("__shared/app/views/shared/_system_signal.html.erb")

    assert_includes flash, 'render "shared/system_signal"'
    assert_includes flash, 'state:, classes: ["flash", "flash--#{type}"], content:'
    assert_includes signal, 'class: classes'
    assert_includes signal, 'aria: { live: aria_live }'
  end

  def test_amber_post_like_uses_shared_feed_action_anatomy
    button = read("amber/app/views/posts/_like_button.html.erb")
    icons = read("__shared/app/views/shared/_feed_icon.html.erb")

    assert_includes button, 'class: "feed-action"'
    assert_includes button, 'aria: { label: t("post.like_count", count: post.likes_count),'
    assert_includes button, 'form_class: "feed-action-form"'
    assert_includes button, 'name: "like"'
    assert_includes button, 'post.likes_count.to_i.positive? ? post.likes_count : ""'
    assert_includes icons, '"like" => :like'
  end

  def test_amber_post_feed_and_detail_share_the_reading_anatomy
    feed = read("amber/app/views/posts/_post.html.erb")
    show = read("amber/app/views/posts/show.html.erb")
    css = amber_css_source

    brgen_feed = read("brgen/app/views/posts/_post.html.erb")

    # Brgen and Amber share the same feed-card anatomy and vote rail. Product
    # identity belongs to the surrounding shell, not a second post treatment.
    card = read("__shared/app/views/shared/_post_card.html.erb")
    assert_includes feed, 'render "shared/post_card"'
    assert_includes brgen_feed, 'render "shared/post_card"'
    refute_includes feed, 'variant:'
    refute_includes brgen_feed, 'variant:'
    refute_includes card, "if variant == :prose"
    refute_includes card, "post-reading-card feed-post"
    assert_includes card, 'class: "feed-card post-reading-card"'
    refute_includes card, "avatar_url"
    refute_includes brgen_feed, "avatar_url:"
    refute_includes brgen_feed, 'class: "feed-card"'
    shared_post_css = read("__shared/app/assets/stylesheets/_post_voting.scss")
    assert_includes shared_post_css, ".feed-card.post-reading-card {\n  margin: 0;\n  padding: var(--space-4) var(--space-3);"
    assert_match(/@media \(min-width: 480px\) \{\s*\.feed-card\.post-reading-card \{\s*padding: var\(--space-5\) var\(--space-4\);/m, shared_post_css)
    assert_includes shared_post_css, ".feed-card.post-reading-card .feed-card-actions {"
    assert_match(/@media \(min-width: 640px\) \{\s*\.feed-card\.post-reading-card \.feed-card-actions \{\s*width: auto;/m, shared_post_css)
    assert_includes shared_post_css, "border-radius: var(--radius-pill);"
    assert_includes shared_post_css, '.feed-card.post-reading-card .feed-card-name a,'
    assert_includes shared_post_css, "padding-block: max(0px, (var(--tap-min) - 1lh) / 2);"
    assert_includes shared_post_css, ".feed-card.post-reading-card .feed-card-time {\n  font-variant-numeric: tabular-nums;"
    assert_includes feed, 'class: "feed-action"'
    assert_includes feed, 'form_class: "feed-action-form"'
    luxury_titles = css[/body\[data-surface="luxury"\] :is\((.*?)\n\) \{/m, 1]
    refute_nil luxury_titles, "Amber luxury heading selector should remain explicit"
    refute_match(/\.post-reading-title/, luxury_titles, "feed cards keep the shared family title face")
    # The detail page's h1 repeats the body's opening words, so it is for
    # screen readers only and has no printed title rule.
    assert_includes show, 'class: "visually-hidden"'
    refute_match(/\.post-show-reading \.post-reading-title \{/, css)
    assert_includes feed, 'show_votes: true'
    assert_includes feed, 'post_url: post_path(post)'
    # The read-more link lives in the shared card the feed renders.
    assert_includes feed, 'render "shared/post_card"'
    assert_includes read("__shared/app/views/shared/_post_card.html.erb"), "link_to more_label, post_url"
    assert_includes show, 'render "shared/post_vote_rail"'
    assert_includes show, 'class="post-show-actions feed-card-actions"'
    assert_includes css, ".post-show-comments"
  end

  def test_amber_enum_selectors_localize_labels_and_keep_enum_values
    helper = read("amber/app/helpers/application_helper.rb")
    season_views = %w[outfits/index.html.erb outfits/_form.html.erb items/_form.html.erb ai/suggest_outfits.html.erb]
    item_form = read("amber/app/views/items/_form.html.erb")
    category_filter = read("amber/app/views/items/_live_search_results.html.erb")
    en = YAML.safe_load_file(File.join(ROOT, "amber/config/locales/en.yml")).fetch("en")
    nb = YAML.safe_load_file(File.join(ROOT, "amber/config/locales/nb.yml")).fetch("nb")

    assert_includes helper, "def amber_enum_options(values, scope:)"
    assert_includes helper, 'values.map do |value|'
    assert_includes helper, '[t("#{scope}.#{key}"), value]'
    {
      "outfits.seasons" => {
        "spring" => ["Spring", "Vår"], "summer" => ["Summer", "Sommer"],
        "autumn" => ["Autumn", "Høst"], "winter" => ["Winter", "Vinter"],
        "all_season" => ["All-season", "Hele året"]
      },
      "items.item_categories" => {
        "tops" => ["Tops", "Topper"], "bottoms" => ["Bottoms", "Underdeler"],
        "dresses" => ["Dresses", "Kjoler"], "shoes" => ["Shoes", "Sko"],
        "accessories" => ["Accessories", "Tilbehør"], "outerwear" => ["Outerwear", "Yttertøy"]
      },
      "items.mood_effects" => {
        "energising" => ["Energising", "Energigivende"], "calming" => ["Calming", "Beroligende"],
        "confident" => ["Confident", "Selvsikker"], "playful" => ["Playful", "Leken"],
        "neutral" => ["Neutral", "Nøytral"]
      },
      "items.life_phases" => {
        "current" => ["Current", "Nåværende"], "past_self" => ["Past self", "Tidligere meg"],
        "aspirational" => ["Aspirational", "Ønsket meg"]
      }
    }.each do |scope, translations|
      en_values = scope.split(".").reduce(en) { |node, key| node.fetch(key) }
      nb_values = scope.split(".").reduce(nb) { |node, key| node.fetch(key) }
      translations.each do |key, (english, norwegian)|
        assert_equal english, en_values.fetch(key), "en #{scope}.#{key}"
        assert_equal norwegian, nb_values.fetch(key), "nb #{scope}.#{key}"
      end
    end

    season_views.each do |view|
      source = read("amber/app/views/#{view}")
      assert_includes source, "amber_season_options", "#{view} should use canonical translated season options"
      refute_match(/f\.select :season, Item::SEASONS/, source, "#{view} must not expose enum values as labels")
    end
    assert_includes helper, 'def amber_season_options = amber_enum_options(Item::SEASONS, scope: "outfits.seasons")'
    assert_includes helper, 'def amber_item_category_options = amber_enum_options(Item::CATEGORIES, scope: "items.item_categories")'
    assert_includes helper, 'def amber_mood_effect_options = amber_enum_options(Item::MOOD_EFFECTS, scope: "items.mood_effects")'
    assert_includes helper, 'def amber_life_phase_options = amber_enum_options(Item::LIFE_PHASES, scope: "items.life_phases")'
    assert_includes item_form, 'f.select :category, amber_item_category_options'
    assert_includes item_form, 'f.select :mood_effect, amber_mood_effect_options'
    assert_includes item_form, 'f.select :life_phase, amber_life_phase_options'
    assert_includes category_filter, "*amber_item_category_options"
    refute_includes category_filter, 'Item::CATEGORIES.each do |category|'
  end
  def test_amber_prioritizes_owned_clothes_and_reversible_lifecycle
    index = read("amber/app/views/items/index.html.erb")
    show = read("amber/app/views/items/show.html.erb")
    form = read("amber/app/views/items/_form.html.erb")
    outfit = read("amber/app/views/outfits/_outfit.html.erb")
    ai = read("amber/app/views/ai/suggest_outfits.html.erb")

    assert_localised "amber", "items/index.html.erb", "wardrobe.use_what_i_own", "Use what I own"
    assert_localised "amber", "items/index.html.erb", "wardrobe.shop_gap", "Shop only for a gap"
    # The invariant is that archiving is *reversible*, which it is: the view
    # offers "Archive to memory" and "Restore to wardrobe" as a pair. The old
    # assertion demanded the literal copy "Archive reversibly", which the UI has
    # never used — so it failed while the behaviour it guards was correct.
    assert_match(/items\.archive|Archive to memory/, show)
    assert_match(/items\.restore|Restore to wardrobe/, show)
    # The disclosure is t("items.photo_processing_html"), so the promised phrase
    # lives in the locale value and never appears in the template. Asserting the
    # English literal against the view failed on a form that renders it
    # correctly — the same mistake as the archive assertion above, and the
    # reason RAILS tests assert through keys rather than English.
    assert_includes form, %(t("items.photo_processing_html"))
    assert_includes en_value("amber", "items.photo_processing_html"), "Photo processing:"
    assert_includes outfit, "outfit-composition"
    assert_includes ai, %(t("ai.why_it_works"))
    assert_includes en_value("amber", "ai.why_it_works"), "Why it works:"
  end

  def test_bsdports_exposes_operator_decisions_and_uncertainty
    index = read("bsdports/app/views/ports/index.html.erb")
    show = read("bsdports/app/views/ports/show.html.erb")
    # The keyboard-first shortcut moved out of a bsdports-local
    # search_hotkey_controller.js — which bound / and Cmd-K on the ports index and
    # nowhere else — into the shared feed-hotkey controller registered on every
    # layout. The claim being pinned is "/ focuses search", not which file holds it.
    hotkey = read("__shared/frontend/feed_hotkey_controller.js")
    layout = read("bsdports/app/views/layouts/application.html.erb")

    # Through the locale, not the literal. bsdports is fully translated now, so
    # every one of these sentences lives in ports.* in en.yml and nb.yml — and a
    # test that greps the view for English fails precisely when the app stops
    # shipping English to a default_locale: nb audience. The claim being pinned is
    # that the honest copy exists and says what it says, which the key assertions
    # below check in both languages.
    assert_includes show, "doas pkg_add"
    assert_localised "bsdports", "ports/index.html.erb", "ports.purpose",
                     "Every OpenBSD port: what it is, how to install it, and its known security advisories."
    assert_localised "bsdports", "ports/show.html.erb", "ports.platform_unknown",
                     "branch and architecture unknown"
    assert_localised "bsdports", "ports/show.html.erb", "ports.advisories_none",
                     "Unknown: no advisories are linked in this local index. This is not the same as a verified clean security record."
    assert_localised "bsdports", "ports/show.html.erb", "ports.requires",
                     "Requires"

    # The uncertainty has to survive translation, or the Norwegian reader gets a
    # more confident product than the English one.
    nb = YAML.safe_load_file(File.join(ROOT, "bsdports/config/locales/nb.yml")).fetch("nb")
    assert_includes nb.dig("ports", "platform_unknown"), "ukjent"
    assert_includes nb.dig("ports", "advisories_none"), "Ukjent"
    assert_includes hotkey, 'e.key === "/"'
    assert_match(/e\.key\.toLowerCase\(\) === "k"/, hotkey)
    assert_includes layout, "feed-hotkey"
  end

  # Through the key and the locale file, not the literal in the template. The
  # primer is localised now, so the English spelling only appears in en.yml —
  # and an assertion on the spelling fails on a view that has got more correct.
  # Both halves: the template must name the key, and the key must still carry
  # what a visitor is told before they tap: what starts, and that text survives
  # a failed canvas. The microphone starts with the rest, so nothing promises
  # it waits.
  def test_master_primer_names_consent_and_text_fallback
    master = File.expand_path("../../MASTER/web", __dir__)
    primer = File.read(File.join(master, "app/views/chat/index.html.erb"))
    assert_includes primer, 't("face.primer_consent")'

    consent = YAML.safe_load_file(File.join(master, "config/locales/en.yml"))
                  .fetch("en").fetch("face").fetch("primer_consent")
    assert_includes consent, "Starts visuals, sound and the microphone"
    assert_includes consent, "text remains available if graphics fail"
  end
end
