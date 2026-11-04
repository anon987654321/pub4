# frozen_string_literal: true

require "test_helper"

# .data-state--stale set only border-color on an element whose border is 0,
# so a stale port looked exactly like a fresh one apart from a slight hue.
class StylesheetStaleMarkerTest < ActiveSupport::TestCase
  test "the stale state draws a visible rule" do
    source = Rails.root.join("app/assets/stylesheets/application.scss").read
    block = source[/^\.data-state--stale \{\n(.*?)\n\}/m, 1]
    assert block, "no .data-state--stale block"
    assert_match(/border-inline-start: 2px solid var\(--status-stale-border\);/, block)
  end
end
