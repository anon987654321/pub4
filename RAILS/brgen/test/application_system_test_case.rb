# frozen_string_literal: true

require "test_helper"
require "axe/matchers/be_axe_clean"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # axe-core-capybara ships an RSpec-style matcher (matches?/failure_message),
  # not a Minitest assertion -- bridge it directly rather than pull in RSpec.
  def assert_accessible(page = Capybara.current_session)
    matcher = Axe::Matchers.be_axe_clean
    assert matcher.matches?(page), matcher.failure_message
  end
end
