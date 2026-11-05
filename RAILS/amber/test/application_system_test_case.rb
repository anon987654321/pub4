# frozen_string_literal: true

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # The test environment turns forgery protection off, which also drops the
  # csrf-token meta tag. A browser test serves the page production serves, so a
  # script's write carries the token and the server checks it.
  setup do
    @forgery_protection_was = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @forgery_protection_was }

  def create_user(prefix = "person", password: "password123")
    User.strict_loading(false).create!(email_address: "#{prefix}-#{SecureRandom.hex(4)}@amber.test", password: password)
  end

  # Headless Chrome sends Accept-Language: en and the suite's default is nb, so
  # a page's words are read in whichever language amber negotiated.
  def page_locale = find("html", visible: :all)[:lang]

  def sign_in(user, password: "password123")
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: password
    find("input[type=submit][value='#{I18n.t("auth.sign_in", locale: page_locale)}']").click
    # Turbo follows the redirect in place, so the session row is the evidence.
    assert wait_until { Session.exists?(user_id: user.id) }, "#{user.email_address} did not sign in"
  end

  # A background fetch or a smooth scroll settles after the step that started it.
  def wait_until(seconds = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      return value if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
    value
  end
end
