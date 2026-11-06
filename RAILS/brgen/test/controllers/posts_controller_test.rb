# frozen_string_literal: true

require "test_helper"

class PostsControllerTest < ActionDispatch::IntegrationTest
  test "index renders posts with the shared card and vote rail" do
    city = brgen_city
    user = User.create!(email_address: "post-index-#{SecureRandom.hex(4)}@example.com",
                        password: "password12345", city: city)
    post_record = ActsAsTenant.with_tenant(city) do
      Post.create!(user: user, title: "Shared feed card", content: "A post in the city feed.", city: city)
    end

    host! "brgen.no"
    get posts_url

    assert_response :success
    # The id is the frame's; the article inside carries none, so it is not twice.
    assert_select "turbo-frame#post_#{post_record.id} > article.feed-card.post-reading-card", 1
    assert_select "[id=post_#{post_record.id}]", 1
    assert_select "#post_#{post_record.id} .post-reading-layout", 1
    assert_select "#post_#{post_record.id} .post-vote-rail", 1
  end

  # The card's Copy link and Share passed the URL as data-clipboard-source-value,
  # but the vendored clipboard controller reads a `source` target, so every
  # press threw "Missing target" and copied nothing.
  test "the card's copy and share buttons carry their URL to a controller that reads it" do
    city = brgen_city
    user = User.create!(email_address: "post-copy-#{SecureRandom.hex(4)}@example.com",
                        password: "password12345", city:)
    post_record = ActsAsTenant.with_tenant(city) do
      Post.create!(user:, title: "Kopier meg", content: "lenke", city:)
    end

    host! "brgen.no"
    get posts_url

    card = "#post_#{post_record.id}"
    assert_select "#{card} [data-clipboard-source-value]", 0
    assert_select "#{card} button[data-controller='share'][data-action='click->share#copy']", 1
    assert_select "#{card} button[data-controller='share'][data-action='click->share#share']", 1
  end

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

  test "compose with only content derives a tag-free title" do
    host! "brgen.no"
    get root_url
    assert_difference -> { Post.count }, 1 do
      post posts_url, params: { post: { title: "<p>Hello Bergen</p>", content: "<p>Hello Bergen from the dialog</p>" } }
    end
    created = Post.order(:id).last
    assert_equal "Hello Bergen from the dialog", created.title
    assert_redirected_to post_url(created)
  end

  test "show offers Edit and Delete to the post's author only" do
    owner = User.create!(email_address: "post-own-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    other = User.create!(email_address: "post-oth-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.create!(user: owner, title: "Mitt innlegg", content: "body", city: brgen_city)
    host! "brgen.no"

    post session_url, params: { email_address: other.email_address, password: "password12345" }
    get post_url(post)
    assert_select "a[href=?]", edit_post_path(post), 0
    assert_select "form[action=?] input[name=_method][value=delete]", post_path(post), 0
    delete session_url

    post session_url, params: { email_address: owner.email_address, password: "password12345" }
    get post_url(post)
    assert_select "a[href=?]", edit_post_path(post), text: I18n.t("actions.edit")
    assert_select "form[action=?][data-turbo-confirm] input[name=_method][value=delete]", post_path(post)
  end

  test "show renders every photo of a gallery post" do
    user = User.create!(email_address: "post-gal-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.new(user:, title: "Tre bilder", content: "body", city: brgen_city)
    3.times { |i| attach_pixel!(post.images, filename: "bilde#{i}.png") }
    post.save!

    host! "brgen.no"
    get post_url(post)

    assert_response :success
    assert_select "article .post-images[data-controller='post-gallery'] a[data-gallery-item] img.post-image", 3
    assert_select "a[aria-label=?]", I18n.t("post.photo_of", number: 2, total: 3, title: "Tre bilder")
  end

  test "a members-only post sends its sign-in back to the post" do
    city = brgen_city
    owner = User.create!(email_address: "club-own-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    member = User.create!(email_address: "club-mem-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    club = ActsAsTenant.with_tenant(city) do
      Community.create!(slug: "lukket-#{SecureRandom.hex(3)}", name: "Lukket", user: owner, city:, privacy: "private")
    end
    CommunityMembership.create!(community: club, user: member)
    post = Post.create!(user: owner, title: "Bare for medlemmer", content: "body", city:, community: club)
    host! "brgen.no"

    get post_url(post)
    assert_response :forbidden
    assert_select "a[href=?]", new_session_path(return_to: post_path(post))

    get new_session_path(return_to: post_path(post))
    assert_select "form[action=?] input[type=hidden][name=return_to][value=?]", session_path, post_path(post)
    credentials = { email_address: member.email_address, password: "password12345" }
    post session_url, params: credentials.merge(return_to: post_path(post))
    assert_redirected_to post_path(post)
  end

  test "the sign-in refuses to send anyone off the site" do
    user = User.create!(email_address: "ret-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    host! "brgen.no"

    credentials = { email_address: user.email_address, password: "password12345" }
    post session_url, params: credentials.merge(return_to: "//evil.example/steal")
    assert_redirected_to root_path
  end

  test "a post refused for a link comes back in the form with the reason, not an empty page" do
    host! "brgen.no"
    get root_url

    assert_no_difference -> { Post.count } do
      post posts_url, params: { post: { title: "Tilbud", content: "<p>Billig hjelp på www.spam-tilbud.com i dag</p>" } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("flash.link_requires_verified_account").squish
    assert_includes response.body, "www.spam-tilbud.com"
  end

  test "show answers markdown for AI and ActivityPub clients" do
    user = User.create!(email_address: "post-md-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.create!(user:, title: "Markdown fixture", content: "A body paragraph.", city: brgen_city)

    host! "brgen.no"
    get post_url(post, format: :md)

    assert_response :success
    assert_match %r{text/markdown}, response.media_type
    assert_includes response.body, "# Markdown fixture"
    assert_includes response.body, "A body paragraph."
  end

  test "an edit to what a post says marks it edited on its page and its card" do
    author = User.create!(email_address: "post-edit-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                          city: brgen_city)
    post_record = ActsAsTenant.with_tenant(brgen_city) do
      Post.create!(user: author, title: "Først", content: "Opprinnelig tekst", city: brgen_city)
    end
    host! "brgen.no"
    post session_url, params: { email_address: author.email_address, password: "password12345" }
    edited = I18n.t("posts.edited", locale: :nb)

    get post_url(post_record)
    assert_select ".feed-post-show-meta .edited-mark", 0

    patch post_url(post_record), params: { post: { content: "Rettet tekst" } }
    post_record.reload
    assert post_record.edited_at, "the edit was not stamped"

    get post_url(post_record)
    assert_select ".feed-post-show-meta .edited-mark", text: edited
    get posts_url
    assert_select "turbo-frame#post_#{post_record.id} .feed-card-meta .edited-mark", text: edited
  end

  test "non-owner cannot update another user's post" do
    owner = User.create!(email_address: "post-owner-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    other = User.create!(email_address: "post-other-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.create!(user: owner, title: "Original", content: "body", city: brgen_city)

    host! "brgen.no"
    post session_url, params: { email_address: other.email_address, password: "password12345" }
    patch post_url(post), params: { post: { title: "Hijacked" } }

    assert_redirected_to post_url(post)
    assert_equal "Original", post.reload.title
  end

  test "an author cannot edit a post into a community they may not post in" do
    author = User.create!(email_address: "post-move-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                          city: brgen_city)
    club_owner = User.create!(email_address: "post-club-#{SecureRandom.hex(4)}@example.com", password: "password12345",
                              city: brgen_city)
    club = nil
    post_record = nil
    ActsAsTenant.with_tenant(brgen_city) do
      club = Community.create!(user: club_owner, name: "Lukket #{SecureRandom.hex(3)}", privacy: "private")
      post_record = Post.create!(user: author, title: "Min", content: "hei", city: brgen_city)
    end

    host! "brgen.no"
    post session_url, params: { email_address: author.email_address, password: "password12345" }
    patch post_url(post_record), params: { post: { community_id: club.id } }

    assert_nil post_record.reload.community_id, "the post moved into a community its author cannot post in"
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
    owner = User.create!(email_address: "post-owner2-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    other = User.create!(email_address: "post-other2-#{SecureRandom.hex(4)}@example.com", password: "password12345")
    post = Post.create!(user: owner, title: "Original", content: "body", city: brgen_city)

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

  test "index leaves out posts by people the reader blocks" do
    city = brgen_city
    reader, blocked = %w[reader blocked].map do |role|
      User.create!(email_address: "post-#{role}-#{SecureRandom.hex(4)}@example.com", password: "password12345", city:)
    end
    theirs = ActsAsTenant.with_tenant(city) { Post.create!(user: blocked, title: "Blokkert", content: "x", city:) }
    reader.block!(blocked)

    host! "brgen.no"
    post session_path, params: { email_address: reader.email_address, password: "password12345" }
    get posts_url

    assert_response :success
    assert_select "#post_#{theirs.id}", 0
  end
end
