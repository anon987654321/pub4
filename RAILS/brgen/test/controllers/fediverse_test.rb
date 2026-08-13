# frozen_string_literal: true

require "test_helper"

# brgen is already partitioned by city subdomain, so a city is already shaped
# like an instance: @kari@brgen.no and @kari@oshlo.no are different accounts.
# Most of what is pinned here is that the city boundary holds.
class FediverseTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @other_city = City.where.not(id: @city.id).first
    @user = User.strict_loading(false).create!(
      email_address: "fedi_kari@brgen.no", password: "password123",
      username: "kari", guest: false, city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def ap_headers = { "Accept" => "application/activity+json" }

  test "webfinger resolves a local account" do
    host! "brgen.no"

    get webfinger_path(resource: "acct:kari@brgen.no")
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "acct:kari@brgen.no", body["subject"]
    assert_equal "https://brgen.no/users/kari", body["links"].first["href"]
  end

  # The city boundary is the whole point: answering for the wrong city would
  # hand a stranger's posts to whoever asked.
  test "webfinger refuses an account from another city's domain" do
    skip "needs a second seeded city" if @other_city.nil?
    host! @other_city.domain

    get webfinger_path(resource: "acct:kari@brgen.no")
    assert_response :not_found
  end

  test "webfinger refuses an unknown account and a malformed resource" do
    host! "brgen.no"

    get webfinger_path(resource: "acct:nobody@brgen.no")
    assert_response :not_found

    get webfinger_path(resource: "kari")
    assert_response :not_found
  end

  test "a guest account is not federated" do
    guest = User.strict_loading(false).create!(
      email_address: "fedi_guest@brgen.no", password: "password123",
      username: "ghost", guest: true, city: @city
    )
    refute guest.federated?

    host! "brgen.no"
    get webfinger_path(resource: "acct:ghost@brgen.no")
    assert_response :not_found
  end

  test "the actor document carries a key and the endpoints a peer needs" do
    host! "brgen.no"

    get "/users/kari", headers: ap_headers
    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "Person", body["type"]
    assert_equal "https://brgen.no/users/kari", body["id"]
    assert_equal "kari", body["preferredUsername"]
    assert_equal "https://brgen.no/users/kari/inbox", body["inbox"]
    assert_equal "https://brgen.no/inbox", body.dig("endpoints", "sharedInbox")
    assert_match "BEGIN PUBLIC KEY", body.dig("publicKey", "publicKeyPem").to_s
  end

  # The keypair is generated on first use, not at signup: brgen mints a real
  # User row for every cookieless visitor and RSA-2048 for each of those would
  # be slow and pointless.
  test "the keypair is minted on demand and then reused" do
    assert_nil @user.reload.private_key

    host! "brgen.no"
    get "/users/kari", headers: ap_headers
    first = @user.reload.public_key
    assert first.present?

    get "/users/kari", headers: ap_headers
    assert_equal first, @user.reload.public_key, "a second fetch must not rotate the key"
  end

  test "the same URL still serves the HTML profile to a browser" do
    host! "brgen.no"

    get "/users/kari"
    assert_response :success
    refute_match "publicKeyPem", response.body
  end

  test "the outbox carries public posts and never a removed one" do
    public_post = Post.create!(user: @user, title: "Sol pa Floyen #{SecureRandom.hex(3)}", content: "Fint")
    removed = Post.create!(user: @user, title: "Fjernet #{SecureRandom.hex(3)}", content: "Nei")
    removed.update!(removed_at: Time.current)

    host! "brgen.no"
    get "/users/kari/outbox", headers: ap_headers
    assert_response :success

    body = response.body
    assert_match public_post.title, body
    refute_match removed.title, body, "an outbox is what relays read; a takedown must not survive in it"
  end

  # Who follows a small-city account is a social graph worth more to a scraper
  # than to anyone else, and nothing in the protocol requires publishing it.
  test "the followers collection reports a count without listing anyone" do
    actor = FediActor.create!(uri: "https://remote.example/users/ola", inbox_url: "https://remote.example/inbox")
    FediFollow.create!(fedi_actor: actor, user: @user, state: "accepted")

    host! "brgen.no"
    get "/users/kari/followers", headers: ap_headers
    body = JSON.parse(response.body)

    assert_equal 1, body["totalItems"]
    assert_empty body["orderedItems"]
  end

  test "nodeinfo describes the city as the instance" do
    host! "brgen.no"

    get "/.well-known/nodeinfo"
    assert_response :success
    assert_match "nodeinfo/2.1", response.body

    get nodeinfo_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ "activitypub" ], body["protocols"]
    assert_equal @city.name, body.dig("metadata", "nodeName")
  end
end
