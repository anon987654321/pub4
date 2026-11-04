# frozen_string_literal: true

require "test_helper"

# What a fetched actor document may put in the key cache, and how a rotated
# remote key is picked up. Client.get_json is replaced for each test, so no
# request leaves the machine.
class FediverseActorFetcherTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "fetch_kari@brgen.no", password: "password123", username: "kari", guest: false, city: @city
    )

    @uri = "https://remote.example/users/ola"
    @key = OpenSSL::PKey::RSA.new(2048)
    @fetched = []
    @original_get_json = Fediverse::Client.method(:get_json)
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    original = @original_get_json
    Fediverse::Client.define_singleton_method(:get_json) { |*args| original.call(*args) }
    ActsAsTenant.current_tenant = nil
  end

  def serve(documents)
    fetched = @fetched
    Fediverse::Client.define_singleton_method(:get_json) { |url| (fetched << url) && documents[url] }
  end

  def document(id: @uri, owner: @uri, key: @key)
    {
      "id" => id, "type" => "Person", "preferredUsername" => "ola",
      "inbox" => "#{id}/inbox",
      "publicKey" => { "id" => "#{id}#main-key", "owner" => owner, "publicKeyPem" => key.public_key.to_pem }
    }
  end

  def deliver(key:)
    body = {
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "https://remote.example/activities/#{SecureRandom.uuid}",
      "type" => "Follow", "actor" => @uri, "object" => "https://brgen.no/users/kari"
    }.to_json
    headers = Fediverse::Signature.sign(
      key:, key_id: "#{@uri}#main-key", method: :post, url: "https://brgen.no/inbox", body:
    )
    host! "brgen.no"
    post "/inbox", params: body, headers: headers.merge("CONTENT_TYPE" => "application/activity+json")
  end

  test "a document that is not the actor asked for is not stored" do
    assert_nil Fediverse::ActorFetcher.upsert(@uri, document(id: "https://remote.example/users/someone-else"))
    assert_nil FediActor.find_by(uri: @uri)
  end

  test "a key that names another owner is not cached" do
    actor = Fediverse::ActorFetcher.upsert(@uri, document(owner: "https://remote.example/users/someone-else"))

    assert actor
    assert_nil actor.public_key_pem
  end

  test "a profile URL is stored under the actor's canonical id" do
    profile = "https://remote.example/@ola"
    serve(profile => document, @uri => document)

    actor = Fediverse::ActorFetcher.find_or_fetch(profile)

    assert_equal @uri, actor&.uri
    assert_nil FediActor.find_by(uri: profile)
  end

  test "a rotated remote key is fetched once and the delivery accepted" do
    old_key = OpenSSL::PKey::RSA.new(2048)
    FediActor.create!(uri: @uri, inbox_url: "#{@uri}/inbox", username: "ola", domain: "remote.example",
                      public_key_pem: old_key.public_key.to_pem, last_fetched_at: 2.hours.ago)
    serve(@uri => document)

    deliver(key: @key)

    assert_response :accepted
    assert_equal [ @uri ], @fetched
    assert_equal @key.public_key.to_pem, FediActor.find_by!(uri: @uri).public_key_pem
  end

  test "a bad signature on a freshly fetched key does not fetch again" do
    FediActor.create!(uri: @uri, inbox_url: "#{@uri}/inbox", username: "ola", domain: "remote.example",
                      public_key_pem: @key.public_key.to_pem, last_fetched_at: Time.current)
    serve(@uri => document)

    deliver(key: OpenSSL::PKey::RSA.new(2048))

    assert_response :unauthorized
    assert_empty @fetched
  end
end
