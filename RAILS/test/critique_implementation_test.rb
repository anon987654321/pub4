# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/scss"
require_relative "support/critique_sources"

class CritiqueImplementationTest < Minitest::Test
  include CritiqueSources

  def test_brgen_has_one_ranking_control_local_voice_and_accessible_actions
    layout = read("brgen/app/views/layouts/application.html.erb")
    home = read("brgen/app/views/home/index.html.erb")
    post = read("brgen/app/views/posts/_post.html.erb")
    compose = read("brgen/app/views/shared/_feed_compose.html.erb")
    feed_actions = Operator::ScssRules.matching(brgen_css_source, /\A\.feed-action\z/)

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
    # brgen serves a different city per domain, so the composer heading comes from
    # the locale with the domain's city passed in, and its copy never names one
    # city: oshlo.no once rendered "Post to Bergen".
    assert_includes compose, 't("feed.compose_title", city: city_name)'
    refute_match(/Bergen/, en_value("brgen", "feed.compose_title"))
    assert_includes compose, 't("feed.posting_as_guest")'
    assert_equal "Anon", en_value("brgen", "feed.posting_as_guest")
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
    # A long preview ends in a translated "read more" link to the post.
    assert_includes card, "link_to more_label, post_url"
    assert_includes css, ".post-reading-preview"
    assert_includes css, ".feed-action-count:empty"
    assert_includes feed, "AFFILIATE_EVERY = 2"
    # The operator's collage (2026-10-31): six deals a band, each band the next six.
    assert_includes affiliate, "visible_deals.rotate(band * 6).first(6) if brgen_surface"
    assert_includes home_feed, "band: position / Brgen::HomeFeed::AFFILIATE_EVERY"
    assert_includes affiliate, "affiliate_feed_unit--brgen"
    assert_includes home_feed, 'surface: "brgen"'
  end

  def test_brgen_first_feed_image_gets_loading_priority_without_poisoning_the_cache
    feed = read("brgen/app/views/home/_live_search_results.html.erb")
    post = read("brgen/app/views/posts/_post.html.erb")
    media = read("brgen/app/views/home/_media_card.html.erb")

    assert_includes feed, 'render "posts/post", post: post, priority: index.zero?'
    assert_includes post, "cache [I18n.locale, post,"
    assert_includes post, "post.voted_by?(Current.user), reposted, quote, priority]"
    assert_includes post, 'fetchpriority: (priority_image ? "high" : "auto")'
    assert_includes post, 'loading: (priority ? "eager" : "lazy")'
    assert_includes media, 'priority_image = local_assigns.fetch(:media_index, 0).to_i.zero?'
    assert_includes media, 'fetchpriority: (priority_image ? "high" : "auto")'
    assert_includes media, 'loading: (priority_image ? "eager" : "lazy")'
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
    assert_includes partial, "post-vote-button"
    assert_includes partial, "post-vote-score"
    assert_includes stream, 'frame.start_with?("post-vote-")'
    assert_includes stream, 'render "shared/post_vote_rail"'
  end

  def test_messenger_has_four_pane_desktop_contract_and_shared_artifacts
    # The rail's DM row is its own partial, so the inbox stream can redraw it.
    rooms = read("brgen/app/views/conversations/_rooms_rail.html.erb") +
            read("brgen/app/views/conversations/_rail_row.html.erb")
    window = read("brgen/app/views/conversations/show.html.erb")
    channel = read("brgen/app/views/channels/show.html.erb")
    css = brgen_css_source
    artifact = read("__shared/app/views/shared/_messenger_artifacts.html.erb")

    assert_includes rooms, 'class="messenger-rail"'
    assert_includes rooms, 'class="messenger-inbox"'
    assert_includes rooms, 't("messages.unread_badge", count: unread)'
    assert_includes rooms, 'class: "messenger-rail-unread", aria: { hidden: true }'
    assert_includes window, 'render "shared/messenger_artifacts"'
    assert_includes channel, 'render "shared/messenger_artifacts"'
    assert_includes css, "grid-template-columns: 56px 300px minmax(0, 1fr) 360px;"
    assert_includes css, ".messenger-artifact-pane"
    assert_includes artifact, "artifact_voice"
    assert_includes artifact, "artifact_preview"
    assert_includes artifact, "no_artifacts"
  end

  def test_shared_feed_text_uses_the_existing_leading_tokens
    minimal = read("__shared/app/assets/stylesheets/_minimal.scss")

    %w[feed-card-text feed-card-body feed-card-meta].each do |selector|
      assert_match(/\.#{selector}\s*\{[^}]*line-height:\s*var\(--leading-normal\);/m, minimal)
    end
    refute_match(/\.feed-card-(?:text|body|meta)\s*\{[^}]*line-height:\s*1\.5;/m, minimal)
  end

  def test_commerce_polish_keeps_marketplace_and_amber_distinct
    brgen_css = brgen_css_source
    # The former _commerce_polish.scss folded into the merged sheets; amber
    # carries it as its own module, brgen's rules live in its core shell
    # module. The selectors are the contract either way.
    amber_css = amber_css_source
    brgen_polish = brgen_css
    amber_polish = stylesheet_module("amber", "commerce_polish")
    seller = read("brgen_marketplace/app/views/marketplace/stores/show.html.erb")
    item = read("amber/app/views/items/show.html.erb")

    assert_includes brgen_css, 'commerce_polish'
    assert_includes brgen_polish, ".listing-ranking-reasons"
    assert_includes brgen_polish, ".store-seller-center"
    assert_includes amber_css, "module: commerce_polish",
                    "amber's commerce polish must remain its own module in the merged sheet"

    assert_includes amber_polish, ".commerce-fit-suggestion"
    assert_includes amber_polish, ".commerce-fit-reasons"
    assert_match(/\.commerce-fit-source\s*\{[^}]*font-size:\s*var\(--text-extra-small\);/m, amber_polish)
    assert_match(/\.commerce-fit-source\s*\{[^}]*line-height:\s*var\(--leading-tight\);/m, amber_polish)
    refute_match(/\.commerce-fit-source\s*\{[^}]*font-size:\s*11px;/m, amber_polish)
    assert_includes seller, 'class="store-seller-center"'
    # The fit list composes with layout utilities (stack, tag), so assert the class token.
    %w[commerce-fit-list commerce-fit-source commerce-fit-reasons].each do |name|
      assert_match(/class="[^"]*\b#{name}\b[^"]*"/, item)
    end
  end

  def test_brgen_new_post_is_progressive_and_photo_first
    form = read("brgen/app/views/posts/new.html.erb")
    controller = read("__shared/frontend/post_progressive_controller.js")
    boot = read("__shared/frontend/stimulus_boot_brgen.js")
    importmap = read("__shared/config/importmap_baseline.rb")
    css = brgen_css_source

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

  def test_rails_runtime_check_scans_the_rails_tree
    check = read("_runtime_check.sh")

    assert_includes check, "--scan-only --tree=RAILS"
    refute_includes check, "--scan-only --tree=OPENBSD"
    assert_match(/total violations|scan[0-9]*:.*violations/, check)
  end

  def test_brgen_post_detail_renders_all_attached_media
    controller = read("brgen/app/controllers/posts_controller.rb")
    show = read("brgen/app/views/posts/show.html.erb")
    css = brgen_css_source

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
    add_card = read("brgen/app/views/home/_media_add_card.html.erb")
    css = brgen_css_source

    assert_includes home, "home.feed_view"
    assert_includes home, "home.media_wall_view"
    assert_includes controller, "Brgen::HomeFeed.media_only(scope)"
    assert_includes controller, 'scope.with_attached_video if params[:view].to_s == "media"'
    assert_includes feed, 'params[:view].to_s == "media"'
    assert_includes feed, 'render "home/media_card"'
    assert_includes feed, '<% if params[:view].to_s == "media" %>'
    assert_includes feed, 'render "home/media_add_card"'
    assert_includes add_card, "brgen-media-add-link"
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

  def test_post_collections_use_the_shared_semantic_list_contract
    brgen_results = read("brgen/app/views/posts/_live_search_results.html.erb")
    amber_index = read("amber/app/views/posts/index.html.erb")
    amber_home = read("amber/app/views/home/_frontpage_posts.html.erb")
    amber_styles = read("amber/app/assets/stylesheets/application.scss")
    feed_list_css = read("__shared/app/assets/stylesheets/_feed_list.scss")

    assert_includes brgen_results, '<ul class="post-feed feed_list post-card-list" id="posts-feed" role="list">'
    assert_match(/<li>\s*<div data-controller="offline-feed"/m, brgen_results)
    assert_match(/<\/li>\s*<% end %>\s*<\/ul>/m, brgen_results)
    assert_includes amber_index, '<ul class="feed_list post-card-list" id="amber-posts-list" role="list">'
    assert_match(/@posts\.each do \|post\| %>\s*<li><%= render post %><\/li>\s*<% end %>/m, amber_index)
    assert_includes amber_home, '<ul class="feed_list post-card-list" id="amber-home-posts-list" role="list">'
    assert_includes amber_styles, '@include meta.load-css("feed_list");'
    assert_includes feed_list_css, ".feed_list.post-card-list > li {\n  display: block;"
    assert_match(/posts\.each do \|post\| %>\s*<li><%= render "posts\/post", post: post %><\/li>/m, amber_home)
  end

  def test_feed_lists_keep_safari_list_roles_and_post_item_boxes
    feed_paths = %w[
      brgen/app/views/home/_live_search_results.html.erb
      brgen/app/views/hashtags/show.html.erb
      brgen/app/views/bookmarks/index.html.erb
      brgen/app/views/events/index.html.erb
      brgen/app/views/events/_live_search_results.html.erb
      brgen_marketplace/app/views/marketplace/favorites/index.html.erb
      brgen_marketplace/app/views/marketplace/deals/_live_search_results.html.erb
      brgen_radio/tv/app/views/tv/sounds/show.html.erb
      brgen_radio/tv/app/views/tv/shows/index.html.erb
      brgen_radio/playlist/app/views/playlist/playlists/_library.html.erb
      brgen/app/views/posts/_live_search_results.html.erb
      amber/app/views/posts/index.html.erb
      amber/app/views/home/_frontpage_posts.html.erb
    ]
    feed_paths.each do |path|
      source = read(path)
      lists = source.scan(/<ul\b[^>]*\bfeed_list\b[^>]*>/)
      refute_empty lists, "#{path} lost its feed_list collection"
      lists.each do |list|
        assert_match(/\brole="list"/, list, "#{path} must preserve Safari list semantics")
      end
    end

    post_lists = %w[
      brgen/app/views/home/_live_search_results.html.erb
      brgen/app/views/hashtags/show.html.erb
      brgen/app/views/bookmarks/index.html.erb
      brgen/app/views/posts/_live_search_results.html.erb
      amber/app/views/posts/index.html.erb
      amber/app/views/home/_frontpage_posts.html.erb
    ]
    post_lists.each do |path|
      assert_match(/<ul\b[^>]*\bpost-card-list\b[^>]*>/, read(path), "#{path} needs real list-item boxes")
    end
    assert_includes read("__shared/app/assets/stylesheets/_feed_list.scss"),
                    ".feed_list.post-card-list > li {\n  display: block;"

    library = read("brgen_radio/playlist/app/views/playlist/playlists/_library.html.erb")
    assert_operator library.index('render "shared/empty_state"'), :>, library.index("</ul>"),
                    "the playlist empty state must not be a direct child of ul"
  end

  def test_brgen_horizon_matches_messenger_archive_and_has_one_premium_item
    horizon = YAML.safe_load_file(File.join(ROOT, "apps.horizon.yml"))
                   .fetch("horizon").fetch("brgen")
    core = horizon.fetch("core")
    dating = horizon.fetch("subapp_dating")

    refute core.any? { |item| item.fetch("name") == "messenger conversation archive" },
           "the archive is implemented and must not remain planned"
    premium = dating.select { |item| item.fetch("name").to_s.start_with?("premium memberships / boost") }
    assert_equal 1, premium.length, "dating premium/boost purchases should be one roadmap item"
    assert_includes premium.first.fetch("name"), "super-like"

    conversation = read("brgen_messenger/app/models/conversation.rb")
    controller = read("brgen_messenger/app/controllers/conversations_controller.rb")
    assert_includes conversation, "scope :in_archive"
    assert_includes controller, "@archive = params[:arkiv].present?"
  end
end
