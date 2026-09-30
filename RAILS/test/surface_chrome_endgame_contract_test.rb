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
    source = source("brgen/app/assets/stylesheets/application.scss")
    include_line = "@include endgame.brgen;"

    [".radio-home-header {", ".radio-track-card-art {", ".playlist-transport-bar {",
     "body.vertical-messenger #new_message {", "body.vertical-marketplace .bol-market-hero {"].each do |selector|
      assert_endpoint_after(source, selector, include_line)
    end

    assert_equal source.strip, source.sub(/\n@include endgame\.brgen;\s*\z/, "").strip + "\n@include endgame.brgen;"
  end

  def test_amber_endgame_is_after_late_luxury_and_messenger_rules
    source = source("amber/app/assets/stylesheets/application.scss")
    include_line = "@include endgame.amber;"

    [".feed-post {", ".amber-editorial-nav{", ".amber-messenger-composer textarea,.amber-messenger-composer select {",
     "body[data-surface="luxury"] .item-card--luxury {"].each do |selector|
      assert_endpoint_after(source, selector, include_line)
    end

    assert_equal source.strip, source.sub(/\n@include endgame\.amber;\s*\z/, "").strip + "\n@include endgame.amber;"
  end

  def test_endgame_file_has_no_shadow_or_important_vetoes
    source = source("shared/app/assets/stylesheets/_surface_chrome_endgame.scss")
    refute_includes source, "box-shadow"
    refute_includes source, "!important"
  end
end
