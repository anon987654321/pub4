# frozen_string_literal: true

require "test_helper"
require "bcrypt"

# Every request without a session cookie creates a guest user. Assigning that
# guest's throwaway password through has_secure_password's setter hashed it at
# BCrypt::Engine.cost — 12 in production, 1,025 ms on vm23's single core — so
# crawlers, uptime probes, robots.txt and manifest.json each burned a second of
# CPU to mint an account that can never sign in. Measured 2026-08-01 across
# 275,334 logged requests: 38.9% sat in one 900-1100 ms bucket, versus 18-24 ms
# for the same endpoint once a cookie existed, and the table had accumulated
# 102,778 guest rows.
class GuestSessionCostTest < ActionDispatch::IntegrationTest
  # Rails forces ActiveModel::SecurePassword.min_cost in the test environment, so
  # a test that just checks the resulting cost passes whether or not the guest
  # path bypasses the setter — it did, and it caught nothing. Turning min_cost
  # off for the duration is what makes this assertion mean something: with
  # `guest.password =` restored, the digest comes back at cost
  # #{BCrypt::Engine.cost} and this fails.
  def test_guest_password_is_hashed_at_minimum_cost_even_at_production_settings
    ActiveModel::SecurePassword.min_cost = false
    host! "brgen.no"

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
    host! "brgen.no"
    get root_url
    first = User.where(guest: true).order(:id).last

    reset!
    host! "brgen.no"
    get root_url
    second = User.where(guest: true).order(:id).last

    refute_equal first.id, second.id, "each cookieless visitor gets its own guest"
    assert BCrypt::Password.valid_hash?(first.password_digest)
    refute_equal first.password_digest, second.password_digest,
                 "guests must not share one digest"
  end

  # A guest is not an authenticated user, which is what makes the cheap digest
  # safe: there is no sign-in path it could weaken.
  def test_guest_is_not_authenticated
    host! "brgen.no"
    get root_url
    guest = User.where(guest: true).order(:id).last

    assert guest.guest?, "the auto-created user must be marked as a guest"
  end
end
