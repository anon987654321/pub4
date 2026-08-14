# frozen_string_literal: true

require "test_helper"
require "bcrypt"

# What a visitor with no session cookie costs.
#
# This file used to open "Every request without a session cookie creates a guest
# user", and that was the problem as much as the description. Assigning the
# throwaway password through has_secure_password's setter hashed it at
# BCrypt::Engine.cost — 12 in production, 1,025 ms on vm23's single core — so
# crawlers, uptime probes, robots.txt and manifest.json each burned a second of
# CPU minting an account that can never sign in. Measured 2026-08-01 across
# 275,334 logged requests: 38.9% sat in one 900-1100 ms bucket against 18-24 ms
# for the same endpoint once a cookie existed, and the table had accumulated
# 102,778 guest rows.
#
# That pass fixed the cost per row and left the rows. By 2026-08-14 there were
# 206,497 of them — 10,461 a day, of which one day's 10,463 had ZERO sessions
# between them and ONE authored post.
#
# So the first sighting no longer writes anything. It gets an unsaved ::User,
# which answers every read a view or policy makes, and a marker goes in the
# session. A browser that keeps cookies returns it and gets a row; a crawler
# that discards them never comes back and never costs one. Both halves are
# pinned below: what a row costs, and when a row is written at all.
class GuestSessionCostTest < ActionDispatch::IntegrationTest
  # The contract, stated as plainly as it can be: one request, no cookie, no row.
  def test_a_single_cookieless_request_writes_no_guest
    host! "brgen.no"

    assert_no_difference -> { User.where(guest: true).count } do
      get root_url
      assert_response :success
    end
  end

  # And the second request does, because by then something has proved it keeps
  # state. In a browser this is immediate — the page it just received fetches the
  # ambient chat frame, and that fetch carries the cookie the response set.
  def test_the_second_request_mints_the_guest
    host! "brgen.no"
    get root_url

    assert_difference -> { User.where(guest: true).count }, 1 do
      get root_url
      assert_response :success
    end
  end

  # Deferring the row must not cost a first-time visitor the thing they did:
  # someone arrives, acts immediately, and the action has to land on a user with
  # a primary key.
  #
  # Two mechanisms hold that up, and this asserts the outcome rather than either
  # one. ensure_guest_user! runs as a before_action for every non-GET, and
  # ActiveRecord independently saves an unsaved belongs_to target before saving
  # the owner, so `votes.find_or_initialize_by(user: Current.user)` persists the
  # guest on its own. Deleting the before_action and re-running the suite leaves
  # this test green and fails exactly one other — RepostsControllerTest, which
  # reads an id before it writes. That is what the before_action is for, and
  # checking rather than assuming is the only reason this comment is accurate.
  def test_a_write_on_the_very_first_request_is_attributed_to_a_real_guest
    host! "brgen.no"
    author = User.create!(email_address: "author-#{SecureRandom.hex(4)}@brgen.no", password: "password123")
    target = Post.create!(user: author, title: "Vote target #{SecureRandom.hex(3)}", content: "…")

    assert_difference -> { User.where(guest: true).count }, 1 do
      post post_vote_path(target), params: { vote: { value: 1 } }
    end

    vote = target.votes.order(:id).last

    assert vote, "the vote must have been recorded"
    assert vote.user.guest?
    assert vote.user.persisted?, "a vote cannot belong to an unsaved user"
    assert_equal vote.user.id, session[:guest_user_id],
                 "the guest persisted mid-request has to be remembered, or the next " \
                 "request builds a new one and the visitor loses what they just did"
  end

  # Rails forces ActiveModel::SecurePassword.min_cost in the test environment, so
  # a test that just checks the resulting cost passes whether or not the guest
  # path bypasses the setter — it did, and it caught nothing. Turning min_cost
  # off for the duration is what makes this assertion mean something: with
  # `guest.password =` restored, the digest comes back at cost
  # #{BCrypt::Engine.cost} and this fails.
  def test_guest_password_is_hashed_at_minimum_cost_even_at_production_settings
    ActiveModel::SecurePassword.min_cost = false
    host! "brgen.no"
    get root_url

    assert_difference -> { User.where(guest: true).count }, 1 do
      get root_url
      assert_response :success
    end

    guest = User.where(guest: true).order(:id).last
    cost = BCrypt::Password.new(guest.password_digest).cost

    assert_equal BCrypt::Engine::MIN_COST, cost,
                 "guest digests must stay at the minimum bcrypt cost — at the production " \
                 "default of #{BCrypt::Engine.cost} this is ~1s of CPU per cookieless request"
  ensure
    ActiveModel::SecurePassword.min_cost = true
  end

  # The digest still has to be a real, per-guest bcrypt hash: unusable because
  # nobody knows the plaintext, not because the field was left blank or shared.
  def test_guest_digest_is_still_unique_and_valid_bcrypt
    first = visit_until_guest_is_minted
    reset!
    second = visit_until_guest_is_minted

    refute_equal first.id, second.id, "each returning visitor gets its own guest"
    assert BCrypt::Password.valid_hash?(first.password_digest)
    refute_equal first.password_digest, second.password_digest,
                 "guests must not share one digest"
  end

  # A guest is not an authenticated user, which is what makes the cheap digest
  # safe: there is no sign-in path it could weaken.
  def test_guest_is_not_authenticated
    guest = visit_until_guest_is_minted

    assert guest.guest?, "the auto-created user must be marked as a guest"
  end

  private

  # Two requests, because one no longer writes a row.
  def visit_until_guest_is_minted
    host! "brgen.no"
    get root_url
    get root_url
    User.where(guest: true).order(:id).last
  end
end
