# frozen_string_literal: true

require "minitest/autorun"

# Source facts about the shared chrome that a rendered page cannot show by
# itself: which tokens exist, which names markup may wear, which strings a
# controller may fall back to. The rendered half is brgen's
# test/system/shared_chrome_behaviour_test.rb and amber's theme_toggle_test.rb.
class SharedChromeSourceContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  STYLES = File.join(ROOT, "__shared/app/assets/stylesheets")

  def read(path) = File.read(File.join(ROOT, path), encoding: "UTF-8")
  def tokens = read("__shared/app/assets/stylesheets/_tokens.scss")

  def app_sources(glob)
    Dir.glob(File.join(ROOT, "{__shared,brgen,brgen_*,amber,bsdports}", "**", glob))
       .reject { _1.include?("/tmp/") || _1.include?("/builds/") || _1.include?("/node_modules/") }
  end

  # shared-001
  def test_no_stylesheet_clears_the_outline_outside_a_pointer_focus_reset
    offenders = app_sources("*.scss").flat_map do |path|
      File.read(path, encoding: "UTF-8").scan(/^([^\n{}]*)\{([^}]*)\}/m).filter_map do |selector, body|
        next unless body.match?(/^\s*outline:\s*(?:none|0)\b/)
        pointer_only = selector.split(",").all? { _1.include?(":focus:not(:focus-visible)") }
        next if pointer_only || selector.include?(".brand-text")

        "#{path.delete_prefix("#{ROOT}/")}: #{selector.strip}"
      end
    end
    assert_empty offenders, "outline cleared outside :focus:not(:focus-visible)"
    refute_match(/!important\s*;/, read("__shared/app/assets/stylesheets/_focus_ring.scss"))
  end

  # shared-011, shared-024
  def test_buttons_hover_only_under_a_hovering_pointer_and_use_the_main_motion_tokens
    buttons = read("__shared/app/assets/stylesheets/_buttons.scss")
    assert_match(/@media \(hover: hover\) \{\s*\.button:hover \{/, buttons)
    stylesheets = app_sources("*.scss").map { File.read(_1, encoding: "UTF-8") }.join
    refute_match(/--(?:ease-m3-spring|duration-m3-short)/, stylesheets)
    assert_includes buttons, "transform var(--transition-fast) var(--ease-spring)"
  end

  # shared-012, shared-014
  def test_markup_names_no_double_dash_modifier_for_avatars_toasts_or_cookie_purposes
    sources = app_sources("*.{erb,rb,js,scss}").reject { _1.include?("/test/") }
    found = sources.select { File.read(_1, encoding: "UTF-8").match?(/\b(?:avatar|toast|cookie-purpose)--\w/) }
    assert_empty found.map { _1.delete_prefix("#{ROOT}/") }
    avatar = read("__shared/app/views/shared/_avatar.html.erb")
    assert_includes avatar, %(t("shared.avatar.alt"))
    refute_includes avatar, %("Avatar")
  end

  # shared-019
  def test_live_search_speaks_only_the_words_its_markup_gives_it
    controller = read("__shared/frontend/live_search_controller.js")
    refute_match(/default: "[A-Z]/, controller, "an English status default is back")
    app_sources("*.erb").each do |path|
      body = File.read(path, encoding: "UTF-8")
      next unless body.match?(/data-controller="live-search|controller: "live-search/)

      %w[updating updated failed].each do |value|
        where = path.delete_prefix("#{ROOT}/")
        assert_match(/live[-_]search[-_]#{value}[-_]value/, body, "#{where} names no #{value} text")
      end
    end
  end

  # shared-045
  def test_root_token_declarations_share_one_indent
    root = tokens[/^  :root \{\n(.*?)^  \}/m, 1]
    outdented = root.lines.grep(/^ {0,3}--/)
    assert_empty outdented
  end

  # shared-046: the half-steps are off the 8px rhythm (tokens.yml scale.space_px),
  # so the fix was the comment that claimed they had joined it.
  def test_no_half_step_spacing_tokens_and_no_claim_that_they_joined_the_scale
    refute_match(/--space-[1-9]\d*-5:/, tokens)
    refute_includes tokens, "joined scale.space_px on"
  end

  # shared-047
  def test_two_scrims
    assert_equal %w[--scrim --scrim-deep], tokens.scan(/^\s*(--scrim[\w-]*):/).flatten
    refute_match(/var\(--scrim-\d+\)/, app_sources("*.scss").map { File.read(_1, encoding: "UTF-8") }.join)
  end

  # shared-048
  def test_luxury_tokens_live_in_amber
    refute_match(/^\s*--luxury-[\w-]+:/, tokens)
    amber = read("amber/app/assets/stylesheets/application.scss")
    %w[--luxury-bg --luxury-surface --luxury-space-large --luxury-font-meta --luxury-line-relaxed].each do |token|
      assert_match(/^\s*#{token}:/, amber, "#{token} is not declared in amber")
    end
  end

  # shared-050, shared-051, shared-052
  def test_one_bundled_mono_and_no_unread_faces
    fonts = read("__shared/app/assets/stylesheets/_fonts.scss")
    faces = fonts.scan(/font-family: "([^"]+)"/).flatten.uniq
    assert_equal [ "JetBrainsMono Nerd Font" ], faces
    refute_includes read("__shared/public/fonts/source-fonts.css"), "Source Code Pro"
    assert_match(/--font-mono: "JetBrainsMono Nerd Font"/, read("__shared/app/assets/stylesheets/_dialect_tokens.scss"))
    Dir.glob(File.join(ROOT, "__shared/public/fonts/*.woff2")).each do |file|
      name = File.basename(file)
      next if name.start_with?("lg.")

      css = fonts + read("__shared/public/fonts/source-fonts.css")
      assert_includes css, name, "#{name} is shipped and no @font-face loads it"
    end
  end
end
