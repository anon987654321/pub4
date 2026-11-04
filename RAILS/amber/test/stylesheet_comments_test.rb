# frozen_string_literal: true

require "test_helper"

# Two stylesheet comments still described a serif display face ("serif
# display", "the serif carries headlines") after amber moved to the Swiss
# sans on 2026-10-11, so the source contradicted the font it sets.
class StylesheetCommentsTest < ActiveSupport::TestCase
  test "no comment describes a serif display face" do
    source = Rails.root.join("app/assets/stylesheets/application.scss").read
    assert_no_match(/serif display|the serif carries/, source)
  end
end
