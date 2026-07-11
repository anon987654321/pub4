# frozen_string_literal: true

require "test_helper"

class Brgen::HomeFeedTest < ActiveSupport::TestCase
  test "following? detects following feed param" do
    assert Brgen::HomeFeed.following?(feed: "following")
    assert_not Brgen::HomeFeed.following?(feed: nil)
    assert_not Brgen::HomeFeed.following?(feed: "for_you")
  end
end