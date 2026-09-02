# frozen_string_literal: true

require "test_helper"

# One row per (route, actor), each declaring ONE outcome.
#
# The flow gates cover this app with GETs carrying an `expect_status` list, and
# twelve of those steps accept 200 AND a redirect — so "serves a stranger" and
# "sends a stranger to sign in" are the same result to the gate. amber grew this
# matrix after `GET /items/new` served an anonymous 200 with every gate green;
# this is the same discipline for brgen, and brgen carries the sharper version
# of the bug on record: `PostsController` line 18 says two `require_real_user`
# lines did not make two gates, because the later `only:` replaced the earlier
# one on the same callback rather than adding to it. The chain looked doubly
# guarded and had exactly one gate.
#
# The distinction this file exists to hold is brgen's own: an anonymous visitor
# here is not a visitor with no user. brgen mints `guest_*@guest.local` accounts
# for people who have not signed up — 5,886 of them in production as of
# 2026-09-01 — so `Current.user` is present for a stranger and "is there a user"
# answers nothing. `require_real_user` is the gate that separates a soft guest
# from an account, which makes every row below a test of that word "real".
#
# `vertical_mutations_test.rb` beside this file covers the signed-in half of the
# engines. Neither it nor any other integration test here asserts a single guest
# refusal on the host app.
#
# Two rules make this catch that class:
#
#   1. Exactly one expected outcome per row. :ok or :redirect, never "either".
#   2. Writes are exercised, not just reads. The hole that mattered was POST.
class AuthorizationMatrixTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if defined?(Brgen::CitySeed) && City.table_exists?
    @city = City.find_or_initialize_by(domain: "brgen.no")
    @city.name ||= "Bergen"
    @city.slug ||= "bergen-authz"
    @city.country_code ||= "NO"
    @city.locale ||= "nb"
    @city.currency = "NOK"
    @city.save!
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # path, verb, guest outcome, signed-in outcome, params.
  #
  # :any for the signed-in write half — the row proves the door opens for an
  # account, and a create that fails validation still proves that. The refusal
  # side is the one that must be exact.
  #
  # Params are carried for both actors so a guest is refused on identity rather
  # than on a missing parameter; a 400 from `params.require` would satisfy
  # "not served" for entirely the wrong reason.
  MATRIX = [
    [ "/communities/new", :get,  :redirect, :ok,  {} ],
    [ "/events/new",      :get,  :redirect, :ok,  {} ],
    [ "/notifications",   :get,  :redirect, :ok,  {} ],
    [ "/communities",     :post, :redirect, :any, { community: { name: "Authz", description: "d" } } ],
    # starts_at is required; without it the signed-in row lands on 422 and
    # the assertion reads as a closed door when the door in fact opened.
    [ "/events",          :post, :redirect, :any,
      { event: { title: "Authz", description: "d", starts_at: "2027-01-01 19:00" } } ],
    # reports#create requires a signed GlobalID for a real target before it
    # does anything, so a signed-in row here would be a test of GlobalID
    # signing rather than of the gate. The refusal is the security property and
    # `before_action :require_real_user` carries no `only:`, so the guest row
    # covers every action on the controller.
    [ "/reports",         :post, :redirect, :guest_only, { reason: "spam" } ],
  ].freeze

  # Surfaces deliberately open to anyone, listed rather than skipped, so
  # "public" is a decision recorded here instead of an absence of coverage.
  # Each is `allow_unauthenticated_access` in its controller; this is the reader
  # that notices when one stops being.
  PUBLIC = [
    [ "/",             :get ],
    [ "/events",       :get ],
    [ "/stories",      :get ],
    [ "/search",       :get ],
    [ "/session/new",  :get ],
    [ "/users/new",    :get ],
  ].freeze

  def sign_in!
    user = User.create!(
      email_address: "authz-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", password_confirmation: "password123",
      username: "authz_#{SecureRandom.hex(3)}", city: @city
    )
    session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    secret = Rails.application.key_generator.generate_key("signed cookie")
    verifier = ActiveSupport::MessageVerifier.new(
      secret, digest: "SHA1", serializer: ActiveSupport::MessageEncryptor::NullSerializer
    )
    cookies[:session_id] = verifier.generate(session.id.to_s)
    user
  end

  def assert_outcome(outcome, route, verb, actor)
    case outcome
    when :ok
      assert_response :success, "#{verb.upcase} #{route} as #{actor} should render"
    when :redirect
      assert_response :redirect, "#{verb.upcase} #{route} as #{actor} must NOT be served — " \
                                 "got #{response.status}. An identity gate is missing, or a " \
                                 "second require_real_user replaced the first instead of adding to it."
    when :any
      assert_includes 200..399, response.status, "#{verb.upcase} #{route} as #{actor} errored"
    end
  end

  test "every guarded route refuses a visitor who is not a real user" do
    MATRIX.each do |route, verb, guest_outcome, _, params|
      reset!
      host! "brgen.no"
      public_send(verb, route, params: params)
      assert_outcome(guest_outcome, route, verb, "guest")
    end
  end

  test "the same routes open for a signed-in account" do
    MATRIX.reject { |_, _, _, expected, _| expected == :guest_only }.each do |route, verb, _, user_outcome, params|
      reset!
      host! "brgen.no"
      sign_in!
      public_send(verb, route, params: params)
      assert_outcome(user_outcome, route, verb, "signed-in user")
    end
  end

  test "public surfaces stay open to a visitor with no account" do
    PUBLIC.each do |route, verb|
      reset!
      host! "brgen.no"
      public_send(verb, route)
      assert_response :success, "#{verb.upcase} #{route} must stay reachable without an account"
    end
  end
end
