# frozen_string_literal: true

require "test_helper"
require "axe/matchers/be_axe_clean"

# Browser tests: headless Chrome through Selenium, as brgen runs them, at a
# phone's width because mrdamascy is a phone-first app. bin/ci runs them
# locally (test:system) and skips them on vm23, which has no browser.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]

  # One browser at a time: test_helper parallelizes by processor, and a Chrome
  # per worker is more than this Mac or the CI box can hold.
  parallelize(workers: 1)

  # A cold Puma on a loaded machine can take longer than Capybara's default.
  # The mock payment pages are absolute URLs built from the routes' default
  # host (localhost:3000 in test), so it points at the test server here.
  setup do
    Capybara.default_max_wait_time = 5
    server = Capybara.current_session.server
    @url_options_were = Rails.application.routes.default_url_options.dup
    Rails.application.routes.default_url_options[:host] = "#{server.host}:#{server.port}"
  end

  teardown do
    Rails.application.routes.default_url_options.replace(@url_options_were)
  end

  # The tab bar's cart tab, once a dish is in the cart (its count badge shows).
  def open_cart_from_tab_bar
    within("nav.tab-bar") do
      assert_selector ".tab-badge", text: "1"
      find("a[href='#{cart_path}']").click
    end
    assert_current_path cart_path
  end

  # axe-core-capybara ships an RSpec-style matcher (matches?/failure_message),
  # not a Minitest assertion; bridged as brgen bridges it.
  def assert_accessible(page = Capybara.current_session)
    matcher = Axe::Matchers.be_axe_clean
    assert matcher.matches?(page), matcher.failure_message
  end
end
