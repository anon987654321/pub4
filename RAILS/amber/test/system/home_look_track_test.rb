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

  # At 1440 "Bymorgen" broke inside the word as Bym / orge / n. A look title
  # wraps only between words, in Norwegian and English, at each tile width.
  BROKEN_WORDS = "[...document.querySelectorAll('.amber-look-title')].flatMap((title) => {" \
                 " const node = title.firstChild; let start = 0;" \
                 " return title.textContent.split(' ').filter((word) => {" \
                 " const range = document.createRange(); range.setStart(node, start);" \
                 " range.setEnd(node, start + word.length); start += word.length + 1;" \
                 " return new Set([...range.getClientRects()].map((r) => Math.round(r.top))).size > 1 }) })"

  SPILLED = "[...document.querySelectorAll('.amber-look-title')].filter((title) => {" \
            " const range = document.createRange(); range.selectNodeContents(title);" \
            " const text = range.getBoundingClientRect();" \
            " const tile = title.closest('.amber-look').getBoundingClientRect();" \
            " return text.left < tile.left - 1 || text.right > tile.right + 1 }).map((title) => title.textContent)"

  test "a look title wraps only between words at every tile width" do
    [ 1024, 1280, 1440 ].each do |width|
      current_window.resize_to(width, 900)

      %w[nb en].each do |locale|
        open_home(locale)

        assert_empty evaluate_script(BROKEN_WORDS), "#{locale} at #{width}px"
        assert_empty evaluate_script(SPILLED), "#{locale} spills at #{width}px"
      end
    end
    browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width: 390, height: 844, deviceScaleFactor: 2, mobile: true)
    open_home("nb")
    assert_empty evaluate_script(BROKEN_WORDS), "nb at 390px"
    assert_empty evaluate_script(SPILLED), "nb spills at 390px"
  ensure
    browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    current_window.resize_to(1400, 1000)
  end

  private

  def browser = page.driver.browser

  # Layout only: straight to the page, without turbo-rails' visit hook, which
  # waits for the cable stream and times out on a loaded machine.
  def open_home(locale)
    browser.navigate.to("#{Capybara.current_session.server.base_url}#{root_path(locale:)}")
    assert_selector ".amber-look-title", minimum: 4
  end

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
