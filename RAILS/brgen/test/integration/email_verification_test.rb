# frozen_string_literal: true

require "test_helper"
class EmailVerificationTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.with_tenant(@city) { Community.create!(name: "G#{SecureRandom.hex(3)}") unless Community.exists? }
    host! "brgen.no"
  end

  test "programmatically created users are grandfathered verified (no test breakage)" do
    u = ActsAsTenant.with_tenant(@city) { User.create!(email_address: "prog-#{SecureRandom.hex(4)}@brgen.no", password: "password12345", username: "p_#{SecureRandom.hex(3)}", city: @city) }
    assert u.email_verified?, "non-signup users must be trusted"
  end

  test "public signup creates an unverified account with a token" do
    email = "new-#{SecureRandom.hex(4)}@brgen.no"
    post users_path, params: { accept_terms: "1", accept_age: "1", user: { email_address: email, username: "nb_#{SecureRandom.hex(3)}", password: "password12345", password_confirmation: "password12345" } }
    u = User.find_by(email_address: email)
    assert u, "account should be created"
    assert_not u.email_verified?, "a fresh signup is unverified"
    assert u.email_verification_token.present?
  end

  test "the honeypot silently blocks a bot signup" do
    assert_no_difference -> { User.where(guest: false).count } do
      post users_path, params: { homepage: "http://spam.example", user: { email_address: "bot-#{SecureRandom.hex(4)}@brgen.no", username: "bot_#{SecureRandom.hex(3)}", password: "password12345", password_confirmation: "password12345" } }
    end
  end

  test "an unverified signup is gated from posting until it confirms" do
    email = "gate-#{SecureRandom.hex(4)}@brgen.no"
    post users_path, params: { accept_terms: "1", accept_age: "1", user: { email_address: email, username: "g_#{SecureRandom.hex(3)}", password: "password12345", password_confirmation: "password12345" } }
    community = Community.first
    assert_no_difference -> { Post.count } do
      post posts_path, params: { post: { title: "blocked", content: "x", community_id: community.id } }
    end
    User.find_by(email_address: email).tap { |u| get verify_email_path(u.email_verification_token) }
    assert_difference -> { Post.count }, 1 do
      post posts_path, params: { post: { title: "now allowed", content: "x", community_id: community.id } }
    end
  end
end
