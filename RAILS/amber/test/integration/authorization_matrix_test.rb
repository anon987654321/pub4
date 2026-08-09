# frozen_string_literal: true

require "test_helper"

# One row per (route, actor), each declaring ONE outcome.
#
# The flow gates cover 24 journeys and 56 steps, and every one of them is a GET
# with an `expect_status` list. Twelve of those steps accept 200 AND a redirect,
# so "renders the form to anyone" and "sends a stranger to sign in" are the same
# result to the gate. That is not a hypothetical: amber's ItemsController lost
# its identity gate to a callback-narrowing bug (see
# RAILS/test/callback_narrowing_test.rb), anonymous GET /items/new served 200,
# and every gate stayed green.
#
# Two rules make this catch that class:
#
#   1. Exactly one expected outcome per row. :ok or :redirect, never "either".
#   2. Writes are exercised, not just reads. The hole that mattered was POST.
#
# Guest here means a visitor with no session at all. amber mints a soft
# Current.user for anonymous visitors by design (Craigslist-style), so "did a
# user object exist" is not the question — "was this identity allowed to do it"
# is, and that is what require_real_user decides.
class AuthorizationMatrixTest < ActionDispatch::IntegrationTest
  # route, verb, guest outcome, signed-in outcome
  MATRIX = [
    [ "/items",            :get,  :redirect, :ok ],
    [ "/items/new",        :get,  :redirect, :ok ],
    [ "/outfits",          :get,  :redirect, :ok ],
    [ "/wardrobe_items",   :get,  :redirect, :ok ],
    # Writes. The gates exercise none of these, and a write is where an open
    # door actually costs something.
    [ "/items",            :post, :redirect, :any ],
    [ "/outfits",          :post, :redirect, :any ]
  ].freeze

  # Surfaces that are deliberately open to anyone. Listed rather than skipped,
  # so "public" is a decision recorded here instead of an absence of coverage.
  PUBLIC = [
    [ "/",              :get ],
    [ "/session/new",   :get ],
    [ "/registration/new", :get ]
  ].freeze

  def sign_in!
    user = User.strict_loading(false).create!(
      email_address: "matrix-#{SecureRandom.hex(4)}@example.com",
      password: "password", password_confirmation: "password"
    )
    post session_path, params: { email_address: user.email_address, password: "password" }
    user
  end

  def assert_outcome(outcome, route, verb, actor)
    case outcome
    when :ok
      assert_response :success, "#{verb.upcase} #{route} as #{actor} should render"
    when :redirect
      assert_response :redirect, "#{verb.upcase} #{route} as #{actor} must NOT be served — " \
                                 "got #{response.status}. An identity gate is missing or was " \
                                 "narrowed by a duplicate before_action."
    when :any
      assert_includes 200..399, response.status, "#{verb.upcase} #{route} as #{actor} errored"
    end
  end

  test "every guarded route refuses a guest and serves a signed-in user" do
    MATRIX.each do |route, verb, guest_outcome, _|
      reset!
      public_send(verb, route)
      assert_outcome(guest_outcome, route, verb, "guest")
    end
  end

  test "the same routes serve a signed-in user" do
    MATRIX.reject { |_, _, _, expected| expected == :any }.each do |route, verb, _, user_outcome|
      reset!
      sign_in!
      public_send(verb, route)
      assert_outcome(user_outcome, route, verb, "signed-in user")
    end
  end

  test "public surfaces stay open to a visitor with no session" do
    PUBLIC.each do |route, verb|
      reset!
      public_send(verb, route)
      assert_response :success, "#{verb.upcase} #{route} must stay reachable without an account"
    end
  end
end
