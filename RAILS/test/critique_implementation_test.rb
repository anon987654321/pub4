# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require_relative "../../MASTER/tools/scss_rules"

class CritiqueImplementationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path) = File.read(File.join(ROOT, path))

  # These pages render through I18n, so a literal English string stopped being
  # in the template the moment the page was localised — the assertion failed on
  # a view that had got better. Pin the key in the template and the copy in that
  # app's en.yml: the control still has to say this word, and the check survives
  # the next locale. Two assertions in this file were already rewritten for the
  # same reason; the comments above them explain each case.
  def en_value(app, key)
    locale = YAML.safe_load_file(File.join(ROOT, app, "config", "locales", "en.yml")).fetch("en")
    key.split(".").reduce(locale) { |node, segment| node.fetch(segment) }
  end

  def assert_localised(app, template, key, english)
    assert_includes read("#{app}/app/views/#{template}"), %(t("#{key}"))
    assert_equal english, en_value(app, key), "#{app} en.yml #{key} drifted from the copy #{template} promises"
  end

  def test_brgen_has_one_ranking_control_local_voice_and_accessible_actions
    layout = read("brgen/app/views/layouts/application.html.erb")
    home = read("brgen/app/views/home/index.html.erb")
    post = read("brgen/app/views/posts/_post.html.erb")
    compose = read("brgen/app/views/shared/_feed_compose.html.erb")
    feed_actions = Operator::ScssRules.matching(read("brgen/app/assets/stylesheets/application.scss"), /\A\.feed-action\z/)

    # The single ranking control lives in posts/index, not the layout — the
    # layout's feed tabs are subapp navigation (subapp_nav_items), a different
    # thing. This used to assert "For you · Hot" / "Following · Latest" against
    # the layout; that copy no longer exists anywhere, so the assertion was
    # failing while the feature it guards was present and correct. Assert the
    # control where it actually is, and keep the real invariant: exactly one
    # ranking control, not duplicated onto the home feed.
    posts_index = read("brgen/app/views/posts/index.html.erb")
    assert_includes posts_index, 'class="sort-tabs"'
    { "hot" => "Hot", "fresh" => "Fresh", "top" => "Top" }.each do |key, label|
      assert_localised "brgen", "posts/index.html.erb", "sort.#{key}", label
    end
    refute_includes home, "sort-tabs"
    assert_match(/home\.intro_title|Bergen/, home)
    # Was assert_includes compose, "Post to Bergen" — which pinned the single-city
    # copy in place. brgen serves a different city per domain, so the composer
    # heading has to interpolate: oshlo.no rendered "Post to Bergen" for as long
    # as this assertion held.
    assert_includes compose, "Post to %{city}"
    assert_includes compose, "city: city_name"
    assert_includes compose, "Posting as a guest"
    assert_match(/post\.share|Share post/, post)
    assert_includes post, "shared/post_card"
    # Either spelling, on the feed action's own rule. The stylesheet writes
    # min-height: var(--tap-min) and the token is 44px; pinning the literal made
    # this fail on a card whose tap targets are exactly what the assertion is
    # about. first_screen asserts the token's value, so accepting the name here
    # is not accepting a promise.
    assert feed_actions.any? { |rule| rule.declares?(/min-height:\s*(?:44px|var\(--tap-min\))/) },
           ".feed-action must carry the tap floor"
  end

  def test_brgen_post_sketch_is_a_compact_reading_unit
    post = read("brgen/app/views/posts/_post.html.erb")
    card = read("__shared/app/views/shared/_post_card.html.erb")
    css = read("__shared/app/assets/stylesheets/_minimal.scss")
    feed = read("brgen/lib/brgen/home_feed.rb")
    affiliate = read("__shared/app/views/shared/_affiliate_feed_unit.html.erb")
    home_feed = read("brgen/app/views/home/_live_search_results.html.erb")

    assert_includes post, 'render "shared/post_embed_action"'
    assert_includes post, 'post.comment_count.positive? ? post.comment_count : ""'
    assert_includes card, "feed-card-byline"
    assert_includes card, "post-reading-preview"
    assert_includes card, 'link_to "…", post_url'
    assert_includes css, ".post-reading-preview"
    assert_includes css, ".feed-action-count:empty"
    assert_includes feed, "AFFILIATE_EVERY = 2"
    assert_includes affiliate, 'brgen_surface ? 1 : 8'
    assert_includes affiliate, "affiliate_feed_unit--brgen"
    assert_includes home_feed, 'surface: "brgen"'
  end

  def test_brgen_post_detail_uses_the_shared_vote_rail_beside_the_title
    show = read("brgen/app/views/posts/show.html.erb")
    partial = read("__shared/app/views/shared/_post_vote_rail.html.erb")
    stream = read("brgen/app/views/votes/create.turbo_stream.erb")

    assert_includes show, 'class="post-reading-layout"'
    assert_includes show, 'turbo_frame_tag "post-vote-'
    assert_includes show, 'render "shared/post_vote_rail"'
    assert_includes show, '<%= tag.h1 @post.title %>'
    assert show.index('render "shared/post_vote_rail"') < show.index("<%= tag.h1 @post.title %>")
    assert_includes partial, "post-vote-btn"
    assert_includes partial, "post-vote-score"
    assert_includes stream, 'frame.start_with?("post-vote-")'
    assert_includes stream, 'render "shared/post_vote_rail"'
  end

  def test_messenger_has_four_pane_desktop_contract_and_shared_artifacts
    rooms = read("brgen/app/views/conversations/_rooms_rail.html.erb")
    window = read("brgen/app/views/conversations/show.html.erb")
    channel = read("brgen/app/views/channels/show.html.erb")
    css = read("brgen/app/assets/stylesheets/application.scss")
    artifact = read("__shared/app/views/shared/_messenger_artifacts.html.erb")

    assert_includes rooms, 'class="messenger-rail"'
    assert_includes rooms, 'class="messenger-inbox"'
    assert_includes window, 'render "shared/messenger_artifacts"'
    assert_includes channel, 'render "shared/messenger_artifacts"'
    assert_includes css, "grid-template-columns: 56px 300px minmax(0, 1fr) 360px;"
    assert_includes css, ".messenger-artifact-pane"
    assert_includes artifact, "artifact_voice"
    assert_includes artifact, "artifact_preview"
    assert_includes artifact, "no_artifacts"
  end

  def test_amber_product_detail_uses_photo_first_editorial_geometry
    show = read("amber/app/views/items/show.html.erb")
    css = read("amber/app/assets/stylesheets/application.scss")

    assert_includes show, 'class="luxury-detail-grid"'
    assert_includes show, 'class="luxury-photos"'
    assert_includes show, 'class="luxury-meta"'
    assert_includes css, ".item-detail--luxury .luxury-detail-grid"
    assert_includes css, ".item-detail--luxury .luxury-meta"
  end
  def test_amber_flash_uses_shared_semantic_signal
    flash = read("amber/app/views/shared/_flash.html.erb")
    signal = read("__shared/app/views/shared/_system_signal.html.erb")

    assert_includes flash, 'render "shared/system_signal"'
    assert_includes flash, 'state:, classes: ["flash", "flash--#{type}"], content:'
    assert_includes signal, 'class: classes'
    assert_includes signal, 'aria: { live: aria_live }'
  end

  def test_shared_yep_search_and_affiliate_pens_are_restored
    search = read("__shared/app/assets/stylesheets/_search_yep.scss")
    affiliate = read("__shared/app/views/shared/_affiliate_feed_unit.html.erb")
    affiliate_css = read("__shared/app/assets/stylesheets/_affiliate_feed_unit.scss")
    brgen_css = read("brgen/app/assets/stylesheets/application.scss")

    assert_includes search, "width: 480px;"
    assert_includes search, "box-shadow: rgba(0, 0, 0, 0.25) 0 1px 8px 0;"
    assert_includes search, "border-radius: 16px;"
    assert_includes affiliate, 'data-controller="parallax-tilt"'
    assert_includes affiliate, 'data-parallax-tilt-target="tile"'
    assert_includes affiliate_css, "font-size: 9px;"
    assert_includes affiliate_css, "letter-spacing: 2px;"
    assert_includes affiliate_css, "transition: transform 180ms var(--ease-out)"
    assert_includes brgen_css, ".store-promo-art-cta"
    assert_includes brgen_css, "background: var(--bol-blue);"
    assert_includes brgen_css, "font-size: 14px;"
  end

  def test_yep_search_is_the_shared_rails_search_default
    shared_stack = read("__shared/app/assets/stylesheets/_stack.scss")
    brgen_stack = read("__shared/app/assets/stylesheets/_stack_brgen.scss")
    amber = read("amber/app/assets/stylesheets/application.scss")
    bsdports = read("bsdports/app/assets/stylesheets/application.scss")
    brgen = read("brgen/app/assets/stylesheets/application.scss")

    assert_includes shared_stack, '@forward "search_yep";'
    assert_includes brgen_stack, '@forward "search_yep";'
    assert_includes amber, '@use "stack" as *;'
    assert_includes bsdports, '@use "stack" as *;'
    assert_includes brgen, '@use "stack_brgen" as *;'
  end

  def test_brgen_radio_restores_the_original_eight_track_warp_tunnel
    source = read("brgen/app/javascript/radio_brgen_tunnel.js")
    importmap = read("brgen/config/importmap.rb")

    %w[
      9EGHwkDix78
      jnP3tRG-LZs
      1XJLtZJ9Ook
      t6T-Q6HMbEo
      zoGTC7uROZE
      7611GgbJAbM
      j0z_-7TfPeM
      Fo7WoYn_FEs
    ].each { |id| assert_includes source, id }

    assert_includes source, 'title: "Microphone Master [Extended]"'
    assert_includes source, 'const OPENING_TRACK_ID = "9EGHwkDix78"'
    assert_includes source, "this._bindTilt = bindTilt"
    assert_includes source, "this._bindTilt?.()"
    assert_includes source, "DeviceOrientationEvent"
    assert_includes source, "requestPermission"
    assert_includes source, 'window.addEventListener("deviceorientation", this._tiltHandler, { passive: true })'
    assert_includes source, "float warp = sin"
    assert_includes source, "lineAngleBuf"
    assert_includes source, "gl.drawArrays(gl.LINES"
    assert_includes source, "preserveDrawingBuffer: false"
    assert_includes source, "mode: " + '"radio:tunnel"'
    refute_includes source, "radio_visualizers"
    refute_includes source, "cycleVisualizer"
    refute_includes source, "vizMode"
    refute_includes importmap, 'radio_visualizers'
    refute File.exist?(File.join(ROOT, "brgen/app/javascript/radio_visualizers.js"))
  end

  def test_amber_looks_use_one_3d_mannequin_and_wrapped_photos
    looks = read("amber/app/views/home/_looks.html.erb")
    mannequin = read("amber/app/javascript/controllers/mannequin_3d_controller.js")
    carousel = read("amber/app/javascript/controllers/wardrobe_carousel_controller.js")
    dressing = read("amber/app/views/shared/_dressing_room.html.erb")
    css = read("amber/app/assets/stylesheets/application.scss")

    assert_includes looks, 'data-controller="mannequin-3d"'
    assert_includes looks, "data-mannequin-3d-slides-value"
    assert_includes looks, "responsive_image_url(garment.photos.first, widths: [720])"
    assert_includes mannequin, "drawWrapped"
    assert_includes mannequin, "surfacePoint"
    assert_includes mannequin, "this.rotation"
    assert_includes mannequin, "attendToChange"
    assert_includes mannequin, "this.reducedMotion"
    assert_includes mannequin, "this.attentionTurn = 0.1"
    assert_includes carousel, "amber:mannequin-change"
    assert_includes dressing, 'data-controller="mannequin-3d"'
    assert_includes dressing, "data-mannequin-3d-zones-value"
    assert_includes css, "mannequin-3d"
  end

  def test_amber_mannequin_particles_are_sparse_cool_and_open
    css = read("amber/app/assets/stylesheets/application.scss")
    renderer = read("amber/app/javascript/controllers/mannequin_3d_controller.js")
    mannequin_css = read("amber/app/assets/stylesheets/_mannequin_3d.scss")

    assert_includes css, "--figure-ink: #8eaee3;"
    assert_includes renderer, "for (let i = 0; i < 432; i += 1)"
    assert_includes renderer, '"ambient"'
    assert_includes renderer, "ctx.globalAlpha = 0.06 + geometry.depth * 0.22"
    assert_includes mannequin_css, "--particle-ink: var(--figure-ink);"
    refute_includes mannequin_css, "amber-look-figure::after"
  end

  def test_commerce_polish_keeps_marketplace_and_amber_distinct
    brgen_css = read("brgen/app/assets/stylesheets/application.scss")
    brgen_polish = read("brgen/app/assets/stylesheets/_commerce_polish.scss")
    amber_css = read("amber/app/assets/stylesheets/application.scss")
    amber_polish = read("amber/app/assets/stylesheets/_commerce_polish.scss")
    seller = read("brgen/engines/marketplace/app/views/marketplace/stores/show.html.erb")
    item = read("amber/app/views/items/show.html.erb")

    assert_includes brgen_css, 'commerce_polish'
    assert_includes brgen_polish, ".listing-ranking-reasons"
    assert_includes brgen_polish, ".store-seller-center"
    assert_includes amber_css, '@use "commerce_polish";'
    assert_includes amber_polish, ".commerce-fit-suggestion"
    assert_includes amber_polish, ".commerce-fit-reasons"
    assert_includes seller, 'class="store-seller-center"'
    assert_includes item, 'class="commerce-fit-list"'
    assert_includes item, 'class="commerce-fit-source"'
    assert_includes item, 'class="commerce-fit-reasons"'
  end

  def test_brgen_new_post_is_progressive_and_photo_first
    form = read("brgen/app/views/posts/new.html.erb")
    controller = read("shared/frontend/post_progressive_controller.js")
    boot = read("shared/frontend/stimulus_boot_social.js")
    importmap = read("__shared/config/importmap_baseline.rb")
    css = read("brgen/app/assets/stylesheets/application.scss")

    assert_includes form, 'post-progressive'
    assert_includes form, 'post_progressive_target: "mediaInput"'
    assert_includes form, 'post.new_media_heading'
    assert_includes form, 'post.new_write_heading'
    assert_includes form, 'post.new_text_only'
    assert_includes form, 'data-action="click->post-progressive#back"'
    assert_includes controller, 'this.#show(1)'
    assert_includes controller, 'turbo:submit-start'
    assert_includes controller, 'turbo:submit-end'
    assert_includes controller, 'this.#publishing(true)'
    assert_includes controller, 'setAttribute("aria-busy", active ? "true" : "false")'
    assert_includes controller, "mediaChanged"
    assert_includes form, 'accept: "video/*"'
    assert_includes form, 'accept: "audio/*"'
    assert_includes form, 'post_progressive_target: "mediaInput"'
    assert_includes css, ".post-media-secondary"
    assert_includes form, "post-publishing"
    assert_includes boot, 'import PostProgressive from "pub4/post_progressive"'
    assert_includes boot, 'application.register("post-progressive", PostProgressive)'
    assert_includes importmap, 'pin "pub4/post_progressive"'
  end

  def test_brgen_home_feed_frame_does_not_share_the_feed_list_id
    feed = read("brgen/app/views/home/_live_search_results.html.erb")

    assert_includes feed, 'turbo_frame_tag "home-feed-frame"'
    assert_includes feed, 'id="home-feed"'
  end

  def test_shared_post_card_does_not_silently_rescue_post_routes
    card = read("__shared/app/views/shared/_post_card.html.erb")

    refute_includes card, "post_path(post) rescue nil"
    assert_includes card, "respond_to?(:post_path)"
  end

  def test_rails_runtime_gate_scans_the_rails_tree
    gate = read("_runtime_gate.sh")

    assert_includes gate, "--scan-only --tree=RAILS"
    refute_includes gate, "--scan-only --tree=OPENBSD"
    assert_match(/total violations|scan[0-9]*:.*violations/, gate)
  end

  def test_brgen_post_detail_renders_all_attached_media
    controller = read("brgen/app/controllers/posts_controller.rb")
    show = read("brgen/app/views/posts/show.html.erb")
    css = read("brgen/app/assets/stylesheets/application.scss")

    assert_includes controller, "with_attached_image.with_attached_video.with_attached_audio"
    assert_includes show, 'video_tag @post.video, controls: true'
    assert_includes show, 'audio_tag @post.audio, controls: true'
    assert_includes css, ".post-video"
    assert_includes css, ".post-audio"
  end

  def test_brgen_front_page_exposes_feed_and_media_wall
    home = read("brgen/app/views/home/index.html.erb")
    controller = read("brgen/app/controllers/home_controller.rb")
    feed = read("brgen/app/views/home/_live_search_results.html.erb")
    card = read("brgen/app/views/home/_media_card.html.erb")
    css = read("brgen/app/assets/stylesheets/application.scss")

    assert_includes home, "home.feed_view"
    assert_includes home, "home.media_wall_view"
    assert_includes controller, "Brgen::HomeFeed.media_only(scope)"
    assert_includes controller, 'scope.with_attached_video if params[:view].to_s == "media"'
    assert_includes feed, 'params[:view].to_s == "media"'
    assert_includes feed, 'render "home/media_card"'
    assert_includes feed, '<% if params[:view].to_s == "media" %>'
    assert_includes feed, "brgen-media-add-link"
    assert_includes feed, 'render "home/media_add_card"'
    assert_includes card, "responsive_image_tag(post.image"
    assert_includes card, "video_tag post.video"
    assert_includes card, 'controls: true'
    assert_includes card, 'data-controller="lightbox"'
    assert_includes card, 'data-turbo="false"'
    assert_includes card, "media_index"
    assert_includes card, '<li class="brgen-media-card'
    assert_includes css, ".brgen-media-card--wide"
    assert_includes css, ".brgen-media-card--tall"
    assert_includes css, ".brgen-media-video::-webkit-media-controls-panel"
    assert_includes css, ".brgen-media-lightbox-link"
    assert_includes css, ".brgen-media-wall"
    assert_includes css, ".home-feed-view + .home-feed-view"
    assert_includes css, "body.vertical-messenger #messages article {"
    assert_includes css, "border-block-end: 1px solid var(--border)"
  end

  def test_amber_post_like_uses_shared_feed_action_anatomy
    button = read("amber/app/views/posts/_like_button.html.erb")
    icons = read("__shared/app/views/shared/_feed_icon.html.erb")

    assert_includes button, 'class: "feed-action"'
    assert_includes button, 'aria: { label: t("post.like_count", count: post.likes_count) }'
    assert_includes button, 'form_class: "feed-action-form"'
    assert_includes button, 'name: "like"'
    assert_includes button, 'post.likes_count.to_i.positive? ? post.likes_count : ""'
    assert_includes icons, '"like" => :like'
  end

  def test_amber_post_feed_and_detail_share_the_reading_anatomy
    feed = read("amber/app/views/posts/_post.html.erb")
    show = read("amber/app/views/posts/show.html.erb")
    css = read("amber/app/assets/stylesheets/application.scss")

    assert_includes feed, 'variant: :prose'
    assert_includes feed, 'show_votes: true'
    assert_includes feed, 'post_url: post_path(post)'
    assert_includes feed, 'link_to "…", post_url'
    assert_includes show, 'render "shared/post_vote_rail"'
    assert_includes show, 'class="post-show-actions feed-card-actions"'
    assert_includes css, ".post-show-comments"
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
    hotkey = read("shared/frontend/feed_hotkey_controller.js")
    layout = read("bsdports/app/views/layouts/application.html.erb")

    # Through the locale, not the literal. bsdports is fully translated now, so
    # every one of these sentences lives in ports.* in en.yml and nb.yml — and a
    # test that greps the view for English fails precisely when the app stops
    # shipping English to a default_locale: nb audience. The claim being pinned is
    # that the honest copy exists and says what it says, which the key assertions
    # below check in both languages.
    assert_includes show, "doas pkg_add"
    assert_localised "bsdports", "ports/index.html.erb", "ports.purpose",
                     "Answer three questions quickly: what package is this, can this machine install it, and what does the local advisory index know?"
    assert_localised "bsdports", "ports/show.html.erb", "ports.platform_unknown",
                     "branch unknown · architecture unknown"
    assert_localised "bsdports", "ports/show.html.erb", "ports.advisories_none",
                     "Unknown: no advisories are linked in this local index. This is not the same as a verified clean security record."
    assert_localised "bsdports", "ports/show.html.erb", "ports.requires",
                     "Requires → dependencies"

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
