# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/tools/scss"
require_relative "support/critique_sources"

class CritiqueImplementationSearchTest < Minitest::Test
  include CritiqueSources

  def test_shared_yep_search_and_affiliate_pens_are_restored_from_universal_paths
    search = read("__shared/app/assets/stylesheets/_search_yep.scss")
    affiliate = read("__shared/app/views/shared/_affiliate_feed_unit.html.erb")
    affiliate_css = read("__shared/app/assets/stylesheets/_affiliate_feed_unit.scss")
    brgen_css = brgen_css_source

    assert_includes search, "width: 480px;"
    assert_includes search, "border-radius: 30px;"
    assert_includes search, "box-shadow: none;"
    refute_match(/box-shadow:(?!\s*none\b)/, search)
    assert_includes affiliate, 'data-controller="parallax-tilt"'
    assert_includes affiliate, 'data-parallax-tilt-target="tile"'
    assert_match(/\.affiliate_feed_label\s*\{[^}]*font-size:\s*var\(--text-extra-small\);/m, affiliate_css)
    assert_match(/\.affiliate_feed_label\s*\{[^}]*letter-spacing:\s*var\(--tracking-normal\);/m, affiliate_css)
    assert_match(/\.affiliate_feed_label\s*\{[^}]*line-height:\s*var\(--leading-tight\);/m, affiliate_css)
    refute_match(/\.affiliate_feed_label\s*\{[^}]*font-size:\s*9px;/m, affiliate_css)
    assert_includes affiliate_css, "transition: transform 180ms var(--ease-out)"
    assert_includes brgen_css, ".store-promo-art-cta"
    assert_includes brgen_css, "background: var(--bol-blue);"
    assert_includes brgen_css, "font-size: 14px;"
  end

  def test_yep_search_is_the_shared_rails_default
    stack = read("__shared/app/assets/stylesheets/_stack.scss")
    brgen_stack = read("__shared/app/assets/stylesheets/_stack_brgen.scss")
    %w[amber bsdports].each do |app|
      application = read("#{app}/app/assets/stylesheets/application.scss")
      assert_includes application, '@include meta.load-css("stack")'
    end

    assert_includes stack, '@forward "search_yep";'
    assert_includes brgen_stack, '@forward "search_yep";'
  end

  def test_live_search_expansion_and_keyboard_focus_follow_real_state
    search_form = read("__shared/app/views/shared/_live_search_form.html.erb")
    controller = read("__shared/frontend/live_search_controller.js")
    search_css = read("__shared/app/assets/stylesheets/_search_yep.scss")

    assert_includes search_form, 'class="search<%= " active" if query.to_s.strip.present? %>"'
    assert_includes search_form, "expanded: query.to_s.strip.present?"
    assert_includes controller, 'shell.dataset.state = "loading"'
    assert_includes controller, 'shell.dataset.state = state'
    assert_includes controller, 'getAttribute("aria-controls")'
    assert_includes controller, 'const isEmpty = Boolean('
    assert_includes controller, 'setAttribute("aria-expanded", String(expanded))'
    assert_includes search_css, ".search:has(input:focus-visible)"
    assert_includes search_css, '.search[data-state="loading"]'
    assert_includes search_css, '.search[data-state="empty"]'
    assert_includes search_css, '.search[data-state="error"]'
  end

  def test_brgen_search_palette_semantics_track_open_state
    palette = read("brgen/app/views/shared/_search_palette.html.erb")
    controller = read("__shared/frontend/search_palette_controller.js")

    assert_includes palette, 'data-search-palette-target="trigger"'
    assert_includes palette, 'aria-haspopup="dialog"'
    assert_includes palette, 'aria-expanded="false"'
    assert_includes palette, 'aria-controls="search_palette_dialog"'
    assert_includes palette, 'id="search_palette_dialog"'
    assert_includes controller, 'static targets = ["panel", "trigger"]'
    assert_includes controller, 'String(this.isOpen)'
    assert_includes controller, 'setAttribute("aria-expanded", "true")'
    assert_includes controller, 'setAttribute("aria-expanded", "false")'
  end

  def test_radio_restores_first_party_device_tilt_contract
    source = radio_source
    assert_includes source, "DeviceOrientationEvent"
    assert_includes source, "requestPermission"
    assert_includes source, 'deviceorientation'
    assert_includes source, "this.tilt = { x: 0, y: 0 }"
  end

  def test_yep_search_is_the_shared_rails_search_default
    shared_stack = read("__shared/app/assets/stylesheets/_stack.scss")
    brgen_stack = read("__shared/app/assets/stylesheets/_stack_brgen.scss")
    amber = amber_css_source
    bsdports = read("bsdports/app/assets/stylesheets/application.scss")
    brgen = stylesheet_source("brgen")

    assert_includes shared_stack, '@forward "search_yep";'
    assert_includes brgen_stack, '@forward "search_yep";'
    assert_includes amber, '@include meta.load-css("stack");'
    assert_includes bsdports, '@include meta.load-css("stack")'
    assert_includes brgen, '@include meta.load-css("stack_brgen")'
  end

  def test_yep_search_is_the_shared_rails_default
    stack = read("__shared/app/assets/stylesheets/_stack.scss")
    brgen_stack = read("__shared/app/assets/stylesheets/_stack_brgen.scss")
    %w[amber bsdports].each do |app|
      application = read("#{app}/app/assets/stylesheets/application.scss")
      assert_includes application, '@include meta.load-css("stack")'
    end

    assert_includes stack, '@forward "search_yep";'
    assert_includes brgen_stack, '@forward "search_yep";'
  end

  def test_live_search_expansion_and_keyboard_focus_follow_real_state
    search_form = read("__shared/app/views/shared/_live_search_form.html.erb")
    controller = read("__shared/frontend/live_search_controller.js")
    search_css = read("__shared/app/assets/stylesheets/_search_yep.scss")

    assert_includes search_form, 'class="search<%= " active" if query.to_s.strip.present? %>"'
    assert_includes search_form, "expanded: query.to_s.strip.present?"
    assert_includes controller, 'shell.dataset.state = "loading"'
    assert_includes controller, 'shell.dataset.state = state'
    assert_includes controller, 'getAttribute("aria-controls")'
    assert_includes controller, 'const isEmpty = Boolean('
    assert_includes controller, 'setAttribute("aria-expanded", String(expanded))'
    assert_includes search_css, ".search:has(input:focus-visible)"
    assert_includes search_css, '.search[data-state="loading"]'
    assert_includes search_css, '.search[data-state="empty"]'
    assert_includes search_css, '.search[data-state="error"]'
  end

  def test_brgen_search_palette_semantics_track_open_state
    palette = read("brgen/app/views/shared/_search_palette.html.erb")
    controller = read("__shared/frontend/search_palette_controller.js")

    assert_includes palette, 'data-search-palette-target="trigger"'
    assert_includes palette, 'aria-haspopup="dialog"'
    assert_includes palette, 'aria-expanded="false"'
    assert_includes palette, 'aria-controls="search_palette_dialog"'
    assert_includes palette, 'id="search_palette_dialog"'
    assert_includes controller, 'static targets = ["panel", "trigger"]'
    assert_includes controller, 'String(this.isOpen)'
    assert_includes controller, 'setAttribute("aria-expanded", "true")'
    assert_includes controller, 'setAttribute("aria-expanded", "false")'
  end

  def test_radio_restores_first_party_device_tilt_contract
    source = radio_source
    assert_includes source, "DeviceOrientationEvent"
    assert_includes source, "requestPermission"
    assert_includes source, 'deviceorientation'
    assert_includes source, "this.tilt = { x: 0, y: 0 }"
  end

  def test_brgen_radio_restores_the_original_eight_track_warp_tunnel
    source = radio_source
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

  def test_yep_search_is_the_shared_rails_search_default
    shared_stack = read("__shared/app/assets/stylesheets/_stack.scss")
    brgen_stack = read("__shared/app/assets/stylesheets/_stack_brgen.scss")
    amber = amber_css_source
    bsdports = read("bsdports/app/assets/stylesheets/application.scss")
    brgen = stylesheet_source("brgen")

    assert_includes shared_stack, '@forward "search_yep";'
    assert_includes brgen_stack, '@forward "search_yep";'
    assert_includes amber, '@include meta.load-css("stack");'
    assert_includes bsdports, '@include meta.load-css("stack");'
    assert_includes brgen, '@include meta.load-css("stack_brgen");'
  end
end
