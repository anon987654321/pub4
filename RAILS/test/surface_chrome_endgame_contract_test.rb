# frozen_string_literal: true

require "minitest/autorun"

class SurfaceChromeEndgameContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def source(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def assert_endpoint_after(source, selector, include_line)
    assert_operator source.rindex(selector), :<, source.rindex(include_line),
      "#{selector} must be authored before #{include_line}"
  end

  def test_brgen_endgame_is_after_late_radio_marketplace_and_messenger_rules
    app = source("brgen/app/assets/stylesheets/application.scss")
    endpoint = source("brgen/app/assets/stylesheets/_brgen_shared_overrides.scss")
    features = Dir.glob(File.join(ROOT, "brgen/app/assets/stylesheets/_brgen_*.scss"))
                  .map { |path| File.read(path, encoding: "UTF-8") }.join("\n")
    all_sources = "#{app}\n#{features}"

    [".radio-home-header {", ".radio-track-card-art {", ".playlist-transport-bar {",
     "body.vertical-messenger #new_message", "body.vertical-marketplace .bol-market-hero {"].each do |selector|
      assert_includes all_sources, selector
    end

    assert_includes app, '@include meta.load-css("brgen_shared_overrides");'
    assert_match(/\n@include endgame\.brgen;\s*\z/, endpoint)
  end

  def test_amber_endgame_is_after_late_luxury_and_messenger_rules
    app = source("amber/app/assets/stylesheets/application.scss")
    endpoint = source("amber/app/assets/stylesheets/_amber_shared_overrides.scss")
    features = Dir.glob(File.join(ROOT, "amber/app/assets/stylesheets/_amber_*.scss"))
                  .map { |path| File.read(path, encoding: "UTF-8") }.join("\n")
    all_sources = "#{app}\n#{features}"

    [".feed-post {", ".amber-editorial-nav{", ".amber-messenger-composer textarea,.amber-messenger-composer select",
     'body[data-surface="luxury"] .item-card--luxury {'].each do |selector|
      assert_includes all_sources, selector
    end

    assert_includes app, '@include meta.load-css("amber_shared_overrides");'
    assert_match(/\n@include endgame\.amber;\s*\z/, endpoint)
  end

  def test_endgame_file_has_no_shadow_or_important_vetoes
    source = source("__shared/app/assets/stylesheets/_surface_chrome_endgame.scss")
    # Resetting to none is how the endpoint flattens earlier chrome; any other value is a shadow.
    refute_match(/box-shadow:(?!\s*none\b)/, source)
    refute_includes source, "!important"
  end
end
