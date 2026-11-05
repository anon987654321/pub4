# frozen_string_literal: true

require "application_system_test_case"

# A home look's track is a focusable scroll group. It steps one slide at a
# time from the arrow keys and from the previous/next buttons under it.
class HomeLookTrackTest < ApplicationSystemTestCase
  test "the arrow keys and the previous and next buttons step a look one slide at a time" do
    visit root_path
    locale = page_locale
    track = find("#amber-look-track-0")
    stage = track.ancestor(".amber-look-stage")
    previous = stage.find_button(I18n.t("home.looks.previous", locale: locale), disabled: :all)
    following = stage.find_button(I18n.t("home.looks.next", locale: locale))

    assert previous.disabled?, "previous is disabled at the start of the track"

    press track, :arrow_right
    assert_track_at track, 1

    following.click
    assert_track_at track, 2
    refute previous.disabled?, "previous is enabled once the track has moved"

    previous.click
    assert_track_at track, 1

    press track, :arrow_left
    assert_track_at track, 0
    assert wait_until { previous.disabled? }, "previous is disabled back at the start"
  end

  private

  def press(track, key)
    execute_script("arguments[0].focus()", track)
    page.send_keys(key)
  end

  # The track's scroll position is the start of slide `index`, measured from
  # the first slide as the controller measures it.
  def assert_track_at(track, index)
    distance = "arguments[0].children[arguments[1]].offsetLeft - arguments[0].firstElementChild.offsetLeft"
    gap = -> { evaluate_script("Math.abs(arguments[0].scrollLeft - (#{distance}))", track, index).to_f }
    assert wait_until { gap.call <= 1 }, "track is not at slide #{index}"
  end
end
