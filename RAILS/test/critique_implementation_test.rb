# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class CritiqueImplementationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path) = File.read(File.join(ROOT, path))

  # These pages render through I18n, so a literal English string stopped being
  # in the template the moment the page was localised — the assertion failed on
  # a view that had got better. Pin the key in the template and the copy in that
  # app's en.yml: the control still has to say this word, and the check survives
  # the next locale. Two assertions in this file were already rewritten for the
  # same reason; the comments above them explain each case.
  def assert_localised(app, template, key, english)
    assert_includes read("#{app}/app/views/#{template}"), %(t("#{key}"))
    locale = YAML.safe_load_file(File.join(ROOT, app, "config", "locales", "en.yml")).fetch("en")
    value = key.split(".").reduce(locale) { |node, segment| node.fetch(segment) }
    assert_equal english, value, "#{app} en.yml #{key} drifted from the copy #{template} promises"
  end

  def test_brgen_has_one_ranking_control_local_voice_and_accessible_actions
    layout = read("brgen/app/views/layouts/application.html.erb")
    home = read("brgen/app/views/home/index.html.erb")
    post = read("brgen/app/views/posts/_post.html.erb")
    compose = read("brgen/app/views/shared/_feed_compose.html.erb")
    css = read("brgen/app/assets/stylesheets/_feed_post.scss")

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
    assert_includes compose, "Post to Bergen"
    assert_includes compose, "Posting as a guest"
    assert_match(/post\.share|Share post/, post)
    assert_includes post, "shared/post_card"
    assert_includes css, "min-height: 44px"
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
    assert_includes form, "Photo processing:"
    assert_includes outfit, "outfit-composition"
    assert_includes ai, "Why it works:"
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

    assert_includes index, "can this machine install it"
    assert_includes show, "doas pkg_add"
    assert_includes show, "branch unknown · architecture unknown"
    assert_includes show, "This is not the same as a verified clean security record"
    assert_includes show, "Requires → dependencies"
    assert_includes hotkey, 'e.key === "/"'
    assert_match(/e\.key\.toLowerCase\(\) === "k"/, hotkey)
    assert_includes layout, "feed-hotkey"
  end

  def test_master_primer_names_consent_and_text_fallback
    primer = File.read(File.expand_path("../../MASTER/web/app/views/chat/index.html.erb", __dir__))
    assert_includes primer, "Starts visuals and sound"
    assert_includes primer, "Microphone access is requested only"
    assert_includes primer, "text remains available if graphics fail"
  end
end
