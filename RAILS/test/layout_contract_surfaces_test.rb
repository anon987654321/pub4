# frozen_string_literal: true

require "minitest/autorun"
require_relative "engine_roots"
require_relative "../../MASTER/tools/scss"
require_relative "support/stylesheet_modules"
require_relative "support/layout_contract_sources"

class LayoutContractSurfacesTest < Minitest::Test
  include LayoutContractSources

  def test_rails_layouts_mark_document_surface_and_main
    %w[brgen amber bsdports].each do |app|
      body = File.read(LAYOUTS.fetch(app))
      assert_includes body, 'data-layout="document"', "#{app} missing data-layout"
      assert_includes body, "data-surface=", "#{app} missing data-surface"
      assert_includes body, 'class="skip-link"', "#{app} missing skip-link"
      assert_includes body, 'id="main-content"', "#{app} missing main id"
      assert_includes body, "viewport-fit=cover", "#{app} missing viewport-fit"
    end
  end

  def test_master_chat_is_face_layout
    body = File.read(LAYOUTS.fetch("master_chat"))
    assert_includes body, 'data-layout="face"'
    assert_includes body, 'data-surface="face"'
    assert_includes body, "skip-link"
    assert_includes body, 'href="#prompt-input"'
    assert_includes body, "viewport-fit=cover"
  end

  def test_master_dashboard_is_document_layout
    body = File.read(LAYOUTS.fetch("master_dashboard"))
    assert_includes body, 'data-layout="document"'
    assert_includes body, 'id="main-content"'
    assert_includes body, "skip-link"
    assert_includes body, '<main id="main-content"'
  end

  def test_stack_forwards_layout_chrome
    stack = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_stack.scss"))
    brgen = File.read(File.join(SHARED, "app", "assets", "stylesheets", "_stack_brgen.scss"))
    assert_includes stack, "layout_chrome"
    assert_includes brgen, "layout_chrome"
  end

  # A bar that hides on a timer needs a way back, and on a mouse the edge zone
  # is the only one: the hidden state is translateY(-100%) with opacity 0, so
  # pointerenter can never fire on the element itself. zone defaults to 0 and
  # the controller registers its pointermove listener only when zone > 0, so
  # leaving it unset is a bar that leaves and stays gone -- silently, because
  # touch and keyboard still recover it and only the mouse is stranded.
  def test_brgen_nav_can_come_back_on_a_mouse
    partial = File.read(File.join(ROOT, "brgen/app/views/shared/_nav_swiper.html.erb"))
    zone = partial[/data-nav-autohide-zone-value="(\d+)"/, 1]

    refute_nil zone, "nav_swiper sets no edge zone, so a mouse cannot recover the bar"
    assert_operator zone.to_i, :>, 0

    controller = File.read(File.join(ROOT, "__shared/frontend/nav_autohide_controller.js"))
    assert_includes controller, "if (this.zoneValue > 0)",
                    "the zone guard is what makes an unset zone silent — keep them described together"
  end

  def test_radio_actions_clear_the_persistent_navigation_band
    radio = stylesheet_source("brgen")
    shell = stylesheet_source("brgen")

    mobile_nav = radio.match(/\.radio-nav\s*\{([^}]*)\}/m)&.[](1)
    assert mobile_nav, "radio action links need one base positioning rule"
    assert_match(
      /inset-block-start:\s*calc\(var\(--top-band-block\)\s*\+\s*var\(--nav-swiper-h\)\s*\+\s*var\(--space-4\)\)/,
      mobile_nav,
      "mobile radio actions must clear the brand band and primary nav"
    )

    desktop_nav = radio.match(
      /@media\s*\(min-width:\s*768px\)\s*\{\s*\.radio-nav\s*\{([^}]*)\}/m
    )&.[](1)
    assert desktop_nav, "desktop radio positioning must follow the primary-nav breakpoint"
    assert_match(
      /inset-block-start:\s*calc\(var\(--nav-swiper-h\)\s*\+\s*var\(--space-4\)\)/,
      desktop_nav,
      "desktop radio actions must clear the single nav band"
    )

    assert_shell_counts_safe_area_once(shell)
    assert_includes shell, "inset: var(--nav-swiper-h) 0 0 0;"
  end

  def test_map_hud_clears_the_persistent_navigation_band
    maps = stylesheet_source("brgen")
    shell = stylesheet_source("brgen")

    mobile_hud = maps.match(/body\.vertical-maps \.map-hud\s*\{([^}]*)\}/m)&.[](1)
    assert mobile_hud, "map HUD must have one source positioning rule"
    assert_match(
      /inset-block-start:\s*calc\(var\(--top-band-block\)\s*\+\s*var\(--nav-swiper-h\)\)/,
      mobile_hud,
      "mobile map controls must clear both brand and primary-nav bands"
    )

    desktop_hud = maps.match(
      /@media\s*\(min-width:\s*768px\)\s*\{\s*body\.vertical-maps \.map-hud\s*\{([^}]*)\}/m
    )&.[](1)
    assert desktop_hud, "desktop map positioning must follow the primary-nav breakpoint"
    assert_match(/inset-block-start:\s*var\(--nav-swiper-h\)/, desktop_hud,
                 "desktop map controls must clear the single nav band")

    assert_shell_counts_safe_area_once(shell)
    assert_includes shell, "inset: var(--nav-swiper-h) 0 0 0;"
  end

  def test_theme_root_uses_dynamic_viewport_height
    %w[brgen amber].each do |app|
      assert app_rules(app, /\A\.theme-root\z/).any? { |rule| rule.declares?(/min-height:\s*100dvh/) },
             "#{app}'s .theme-root must size to the dynamic viewport"
    end
  end

  def test_messenger_dock_reads_keyboard_inset
    composer = /\Abody\.vertical-messenger #new_message(?::not\([^)]*\))?\z/
    assert app_rules("brgen", composer).any? { |rule| rule.declares?(/var\(--keyboard-inset/) },
           "the messenger composer must sit above the on-screen keyboard"
  end

  def test_amber_home_preserves_its_large_wordmark_and_editorial_masthead
    styles = File.read(File.join(ROOT, "amber", "app/assets/stylesheets/application.scss"), encoding: "UTF-8")
    # Anchor to the base rules: the sheet also carries a luxury override whose
    # selector ends in .amber-masthead--home, and a minified restore row, and
    # the spacious stage is the base rule's contract.
    masthead_rules = styles.scan(/^\.amber-masthead--home\s*\{([^}]*)\}/m).flatten
    logo_rules = styles.scan(/^\.amber-masthead--home\s+\.amber-logo-home\s*\{([^}]*)\}/m).flatten

    refute_empty masthead_rules, "Amber home masthead rule is missing"
    refute_empty logo_rules, "Amber home wordmark sizing rule is missing"
    assert_match(/min-height:\s*72svh/, masthead_rules.last,
                 "the home mark must retain its spacious first-screen stage")
    assert_match(/align-items:\s*center/, masthead_rules.last)
    assert_match(/width:\s*min\(100%,\s*880px\)/, logo_rules.last,
                 "the home wordmark must not collapse to the 200px interior logo or a 380px cap")
  end

  def test_bsdports_keeps_its_white_google_frontpage_dialect
    layout = File.read(LAYOUTS.fetch("bsdports"), encoding: "UTF-8")
    styles = File.read(File.join(ROOT, "bsdports", "app/assets/stylesheets/application.scss"), encoding: "UTF-8")

    assert_includes layout, %(<meta name="color-scheme" content="light">)
    assert_includes layout, %(<meta name="theme-color" content="#ffffff" data-light-color="#ffffff" data-dark-color="#000000">)
    assert_includes styles, "--text: #202124;"
    assert_includes styles, "--text-secondary: #4d5156;"
    assert_includes styles, "--accent: #1a0dab;"
    assert_match(/--font:\s*Arial,\s*"Helvetica Neue",\s*Helvetica,\s*sans-serif;/, styles)
    assert_includes styles, "color-scheme: light;"
    refute_includes layout, %(<meta name="color-scheme" content="dark">)
  end
end
