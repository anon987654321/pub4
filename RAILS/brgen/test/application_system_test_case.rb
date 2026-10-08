# frozen_string_literal: true

require "test_helper"
require "axe/matchers/be_axe_clean"

# The verticals route by subdomain, and brgen.no's names resolve to vm23. Chrome
# maps every brgen.no host to the test server instead, so a system test visits
# dating.brgen.no the way a person does and the session cookie crosses hosts.
module CityHostSystemTest
  APEX = "brgen.no"

  def self.included(base)
    # Its own driver name: Capybara keeps one session per name, and a session
    # opened by another system test would carry no resolver rules.
    base.driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ],
                              options: { name: :headless_chrome_city_hosts } do |options|
      # A payment provider's host resolves to nothing, so a hand-off never
      # leaves the machine.
      options.add_argument("--host-resolver-rules=MAP #{APEX} 127.0.0.1, MAP *.#{APEX} 127.0.0.1, " \
                           "MAP checkout.stripe.com ~NOTFOUND, MAP *.vipps.no ~NOTFOUND")
    end
    # The test environment turns forgery protection off, which also drops the
    # csrf-token meta tag. A browser test serves the page production serves, so a
    # script's write carries the token and the server checks it.
    base.setup do
      @forgery_protection_was = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
    end
    base.teardown do
      ActionController::Base.allow_forgery_protection = @forgery_protection_was
      Capybara.app_host = nil
    end
  end

  def city_url(subdomain, path)
    host = subdomain ? "#{subdomain}.#{APEX}" : APEX
    "http://#{host}:#{Capybara.current_session.server.port}#{path}"
  end

  def visit_city(subdomain, path) = visit(city_url(subdomain, path))

  def sign_in_on_city(user, password: "password123")
    visit_city(nil, "/session/new")
    fill_in "email_address", with: user.email_address
    fill_in "password", with: password
    find("input[type=submit][value='#{I18n.t("auth.sign_in")}']").click
    # Turbo submits the form and follows the redirect in place, so the address
    # bar is no evidence; the session row is.
    assert wait_until { Session.exists?(user_id: user.id) }, "#{user.email_address} did not sign in"
  end

  # A background fetch commits after the page has moved on.
  def wait_until(seconds = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      return value if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
    value
  end
end

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ]

  # axe-core-capybara ships an RSpec-style matcher (matches?/failure_message),
  # not a Minitest assertion -- bridge it directly rather than pull in RSpec.
  def assert_accessible(page = Capybara.current_session)
    matcher = Axe::Matchers.be_axe_clean
    assert matcher.matches?(page), matcher.failure_message
  end
end
