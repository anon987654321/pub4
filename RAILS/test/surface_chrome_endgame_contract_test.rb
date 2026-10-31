# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/stylesheet_modules"

# One stylesheet per app, operator 2026-10-28: the former partials live in
# application.scss between module banners, and StylesheetModules slices them
# back out. The endgame include has to stay the last rule of its module and the
# module has to sit after the late feature rules, or the chrome reset it
# performs would land before the chrome it resets.
class SurfaceChromeEndgameContractTest < Minitest::Test
  include StylesheetModules

  ROOT = File.expand_path("..", __dir__)

  def source(path)
    File.read(File.join(ROOT, path), encoding: "UTF-8")
  end

  def test_brgen_endgame_is_after_late_radio_marketplace_and_messenger_rules
    app = application_scss("brgen")
    endpoint = stylesheet_module("brgen", "brgen_shared_overrides")

    [".radio-home-header {", ".radio-track-card-art {", ".playlist-transport-bar {",
     "body.vertical-messenger #new_message", "body.vertical-marketplace .bol-market-hero {"].each do |selector|
      assert_includes app, selector
    end

    assert_match(/\n@include endgame\.brgen;\s*\z/, endpoint,
                 "the endgame include must remain the module's last rule")
    assert_operator app.rindex("module: brgen_shared_overrides"), :>,
                    app.rindex(".radio-home-header {"),
                    "the overrides module must load after the late radio, marketplace and messenger rules"
  end

  def test_amber_endgame_is_after_late_luxury_and_messenger_rules
    app = application_scss("amber")
    endpoint = stylesheet_module("amber", "amber_shared_overrides")

    [".feed-post {", ".amber-editorial-nav{", ".amber-messenger-composer textarea,.amber-messenger-composer select",
     'body[data-surface="luxury"] .item-card--luxury {'].each do |selector|
      assert_includes app, selector
    end

    assert_match(/\n@include endgame\.amber;\s*\z/, endpoint,
                 "the endgame include must remain the module's last rule")
    assert_operator app.rindex("module: amber_shared_overrides"), :>,
                    app.rindex(".feed-post {"),
                    "the overrides module must load after the late luxury and messenger rules"
  end

  def test_endgame_file_has_no_shadow_or_important_vetoes
    source = source("__shared/app/assets/stylesheets/_surface_chrome_endgame.scss")
    # Resetting to none is how the endpoint flattens earlier chrome; any other value is a shadow.
    refute_match(/box-shadow:(?!\s*none\b)/, source)
    refute_includes source, "!important"
  end
end
