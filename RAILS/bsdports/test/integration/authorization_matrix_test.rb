# frozen_string_literal: true

require "test_helper"

# One row per (route, actor), each declaring ONE outcome.
#
# The flow gates cover this app with GETs carrying an `expect_status` list, and
# twelve of those steps accept 200 AND a redirect — so "serves a stranger" and
# "sends a stranger to sign in" are the same result to the gate. amber grew this
# matrix after `GET /items/new` served an anonymous 200 with every gate green
# (RAILS/amber/test/integration/authorization_matrix_test.rb); this is the same
# discipline for bsdports, and bsdports has its own version of that bug on
# record: `PortsController` line 8 says watch/unwatch once called
# require_authentication *inside the action body*, where the redirect does not
# halt, so the next line ran find_or_create_by!(user: Current.user) for a
# visitor with no user.
#
# `port_mutations_test.rb` beside this file covers the signed-in half of those
# same routes. It does not assert a single guest refusal, which is the half that
# the bug lived in — reading it green tells you a watch works, not that a
# stranger cannot cast one.
#
# Two rules make this catch that class:
#
#   1. Exactly one expected outcome per row. :ok or :redirect, never "either".
#   2. Writes are exercised, not just reads. Every guarded route here is a write.
class AuthorizationMatrixTest < ActionDispatch::IntegrationTest
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "net-authz",
                                 slug: "net-authz-#{SecureRandom.hex(3)}", description: "net")
    @port = Port.create!(
      platform: @platform, category: @category, name: "curl",
      pkgpath: "net/curl-authz-#{SecureRandom.hex(3)}",
      comment: "Tool for transferring data with URL syntax",
      version: "8.0.0", description: "libcurl client-side URL transfer library"
    )
  end

  # route builder, verb, guest outcome, signed-in outcome, params.
  #
  # :any for the signed-in write half — the row exists to prove the door opens
  # for an account, and a create that fails validation still proves that. The
  # refusal side is the one that must be exact.
  #
  # Params are per row and carried for both actors, so the guest row is refused
  # on identity rather than on a missing parameter: comments#create calls
  # params.require(:comment), and a bare POST returns 400 before any gate is
  # consulted. A 400 would have passed the guest assertion for the wrong reason.
  def matrix
    [
      [ -> { watch_port_path(@port) },        :post,   :redirect, :any, {} ],
      [ -> { unwatch_port_path(@port) },      :delete, :redirect, :any, {} ],
      [ -> { review_port_path(@port) },       :post,   :redirect, :any, {} ],
      [ -> { port_comments_path(@port) },     :post,   :redirect, :any,
        { comment: { content: "Builds clean on 7.6" } } ],
      # crossref_cves reaches NvdCve.crossref, which talks to an external
      # service. Only the guest row runs: the refusal is the security property,
      # and a signed-in row would make this suite depend on the network.
      [ -> { crossref_cves_port_path(@port) }, :post,  :redirect, :guest_only, {} ],
    ]
  end

  # Surfaces deliberately open to anyone, listed rather than skipped, so
  # "public" is a decision recorded here instead of an absence of coverage.
  # Each one is `allow_unauthenticated_access` in its controller; this is the
  # reader that notices when one stops being.
  def public_surfaces
    [
      [ -> { root_path },                :get ],
      [ -> { port_path(@port) },         :get ],
      [ -> { explore_port_path(@port) }, :get ],
      [ -> { categories_path },          :get ],
      [ -> { category_path(@category) }, :get ],
      [ -> { maintainers_path },         :get ],
      [ -> { new_session_path },         :get ],
    ]
  end

  def sign_in!
    user = User.strict_loading(false).create!(
      email_address: "authz-#{SecureRandom.hex(4)}@bsdports.test", password: "password"
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
                                 "got #{response.status}. An identity gate is missing, or it is " \
                                 "inside the action body where its redirect does not halt."
    when :any
      assert_includes 200..399, response.status, "#{verb.upcase} #{route} as #{actor} errored"
    end
  end

  test "every guarded write refuses a visitor with no session" do
    matrix.each do |route, verb, guest_outcome, _, params|
      reset!
      path = instance_exec(&route)
      public_send(verb, path, params: params)
      assert_outcome(guest_outcome, path, verb, "guest")
    end
  end

  test "the same writes open for a signed-in account" do
    matrix.reject { |_, _, _, expected, _| expected == :guest_only }.each do |route, verb, _, user_outcome, params|
      reset!
      sign_in!
      path = instance_exec(&route)
      public_send(verb, path, params: params)
      assert_outcome(user_outcome, path, verb, "signed-in user")
    end
  end

  test "public surfaces stay open to a visitor with no session" do
    public_surfaces.each do |route, verb|
      reset!
      path = instance_exec(&route)
      public_send(verb, path)
      assert_response :success, "#{verb.upcase} #{path} must stay reachable without an account"
    end
  end
end
