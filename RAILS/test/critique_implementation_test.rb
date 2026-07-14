# frozen_string_literal: true

require "minitest/autorun"

class CritiqueImplementationTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def read(path) = File.read(File.join(ROOT, path))

  def test_brgen_has_one_ranking_control_local_voice_and_accessible_actions
    layout = read("brgen/app/views/layouts/application.html.erb")
    home = read("brgen/app/views/home/index.html.erb")
    post = read("brgen/app/views/posts/_post.html.erb")
    compose = read("brgen/app/views/shared/_feed_compose.html.erb")
    css = read("brgen/app/assets/stylesheets/_widgets.scss")

    assert_includes layout, "For you · Hot"
    assert_includes layout, "Following · Latest"
    refute_includes home, "sort-tabs"
    assert_includes home, "Bergen, right now"
    assert_includes compose, "Post to Bergen"
    assert_includes compose, "Posting as a guest"
    assert_includes post, 'aria-label="Share post"'
    assert_includes css, "min-height: 44px"
  end

  def test_amber_prioritizes_owned_clothes_and_reversible_lifecycle
    index = read("amber/app/views/items/index.html.erb")
    show = read("amber/app/views/items/show.html.erb")
    form = read("amber/app/views/items/_form.html.erb")
    outfit = read("amber/app/views/outfits/_outfit.html.erb")
    ai = read("amber/app/views/ai/suggest_outfits.html.erb")

    assert_includes index, "Use what I own"
    assert_includes index, "Shop only for a gap"
    assert_includes show, "Archive reversibly"
    assert_includes show, "Restore to wardrobe"
    assert_includes form, "Photo processing:"
    assert_includes outfit, "outfit-composition"
    assert_includes ai, "Why it works:"
  end

  def test_bsdports_exposes_operator_decisions_and_uncertainty
    index = read("bsdports/app/views/ports/index.html.erb")
    show = read("bsdports/app/views/ports/show.html.erb")
    hotkey = read("bsdports/app/javascript/controllers/search_hotkey_controller.js")

    assert_includes index, "can this machine install it"
    assert_includes show, "doas pkg_add"
    assert_includes show, "branch unknown · architecture unknown"
    assert_includes show, "This is not the same as a verified clean security record"
    assert_includes show, "Requires → dependencies"
    assert_includes hotkey, 'event.key === "/"'
  end

  def test_master_primer_names_consent_and_text_fallback
    primer = File.read(File.expand_path("../../MASTER/web/app/views/chat/index.html.erb", __dir__))
    assert_includes primer, "Starts visuals and sound"
    assert_includes primer, "Microphone access is requested only"
    assert_includes primer, "text remains available if graphics fail"
  end
end
