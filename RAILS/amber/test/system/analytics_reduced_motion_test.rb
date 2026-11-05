# frozen_string_literal: true

require "application_system_test_case"

# The analytics chips count up from zero. A reader who asked the system for
# reduced motion sees the number the server rendered, and it never moves.
class AnalyticsReducedMotionTest < ApplicationSystemTestCase
  # Its own driver name: Capybara keeps one session per name, and this one asks
  # Chrome to report prefers-reduced-motion: reduce.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ],
                       options: { name: :headless_chrome_reduced_motion } do |options|
    options.add_argument("--force-prefers-reduced-motion")
  end

  COUNTER = "[data-controller~='animated-number']"
  # Installed before any page script runs, it keeps every text a counter
  # shows: the parser's first insertion and each frame of an animation.
  RECORDER = File.read(File.expand_path("counter_recorder.js", __dir__))

  test "a reduced-motion reader sees the analytics counts without the count-up" do
    user = create_user("calm")
    3.times { |n| Item.create!(user: user, title: "Coat #{n}", category: "Outerwear") }
    sign_in(user)

    devtools.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: RECORDER)
    visit analytics_wardrobe_items_path
    assert evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches"), "Chrome reports no reduced motion"

    finals = all(COUNTER, minimum: 3).map { |counter| counter[:"data-animated-number-end-value"] }
    assert_includes finals, "3"
    # The animation runs for 500 ms; a full second covers it and its last frame.
    sleep 1
    seen = evaluate_script("window.counterTexts").uniq
    assert_empty seen - finals, "the counters moved through #{seen - finals} on their way to #{finals}"
    assert_equal finals, all(COUNTER).map(&:text).map(&:strip)
  end

  private

  def devtools = page.driver.browser
end
