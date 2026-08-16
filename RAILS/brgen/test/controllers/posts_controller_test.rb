# frozen_string_literal: true

require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  # Post includes CityTenantable -> acts_as_tenant :city. A request to brgen.no
  # sets ActsAsTenant.current_tenant (application_controller.rb:66-69), which
  # scopes every Post query to that city_id. A fixture built out here, with no
  # request in flight, has no tenant and gets city_id: nil — invisible to the
  # scoped query, so the controller 404s.
  #
  # That only bites where a City row for the host actually exists, and the two
  # environments disagreed about exactly that. Measured: the local test database
  # holds 0 cities, so City.find_by(domain: "brgen.no") is nil, the tenant is
  # never set, the query is unscoped and the fixture is found. The VPS seeds 44
  # cities before running the suite, so there the tenant is real. Same code, same
  # commit, opposite results — and the failing side was the one nobody watches.
  #
  # So this creates the city rather than looking it up. Finding it would leave
  # the local run on the untenanted path forever, which is the path that cannot
  # catch this: a test that only exercises the bug on a machine you do not watch
  # is the blind spot, not the fix.
  def brgen_city
    City.find_by(domain: "brgen.no") || City.create!(
      name: "Bergen", slug: "bergen-test-tenant", domain: "brgen.no",
      country_code: "NO", locale: "nb", currency: "NOK"
    )
  end

  test "show renders without a strict_loading violation on post.user" do
    user = User.create!(email_address: "post-show-test-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.create!(user:, title: "Regression fixture", content: "body", city: brgen_city)

    host! "brgen.no"
    get post_url(post)

    assert_response :success
    assert_includes response.body, 'type="application/ld+json"'
  end

  test "non-owner cannot update another user's post" do
    owner  = User.create!(email_address: "post-owner-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    other  = User.create!(email_address: "post-other-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post   = Post.create!(user: owner, title: "Original", content: "body", city: brgen_city)

    host! "brgen.no"
    post session_url, params: { email_address: other.email_address, password: "password12345" }
    patch post_url(post), params: { post: { title: "Hijacked" } }

    assert_redirected_to post_url(post)
    assert_equal "Original", post.reload.title
  end

  test "a private community post is members-only, not a 404" do
    owner = User.create!(email_address: "post-priv-own-#{SecureRandom.hex(4)}@example.com", password: "password12345", city: brgen_city)
    stranger = User.create!(email_address: "post-priv-str-#{SecureRandom.hex(4)}@example.com", password: "password12345", city: brgen_city)
    community = nil
    post_record = nil
    ActsAsTenant.with_tenant(brgen_city) do
      community = Community.create!(user: owner, name: "Hemmelig #{SecureRandom.hex(3)}", privacy: "private")
      community.community_memberships.create!(user: owner, role: "owner")
      post_record = Post.create!(user: owner, community: community, title: "Inne", content: "kun medlemmer", city: brgen_city)
    end

    host! "brgen.no"
    post session_url, params: { email_address: stranger.email_address, password: "password12345" }
    get post_url(post_record)

    assert_response :forbidden
    assert_select "h2.empty-state-title"
  end

  test "non-owner cannot destroy another user's post" do
    owner  = User.create!(email_address: "post-owner2-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    other  = User.create!(email_address: "post-other2-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post   = Post.create!(user: owner, title: "Original", content: "body", city: brgen_city)

    host! "brgen.no"
    post session_url, params: { email_address: other.email_address, password: "password12345" }
    assert_no_difference "Post.count" do
      delete post_url(post)
    end
    # Without this the test passes for the wrong reason: a 404 leaves Post.count
    # unchanged just as convincingly as a refused delete does, so the assertion
    # above stayed green on the VPS while the request never reached the
    # authorization it exists to prove. Naming the redirect is what separates
    # "the guard held" from "the row was never found".
    assert_redirected_to post_url(post)
    assert Post.exists?(post.id), "the post the guard refused to delete should still be there"
  end
end
