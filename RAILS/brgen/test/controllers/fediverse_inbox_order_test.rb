# frozen_string_literal: true

require "test_helper"

# The inbox's free checks run before its one costly step: fetching the
# sender's actor document, from a URL the sender's own header names.
class FediverseInboxOrderTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @key = OpenSSL::PKey::RSA.new(2048)
    @actor_uri = "https://unknown.example/users/ola"
    @fetched = []
    fetched = @fetched
    @original_fetch = Fediverse::ActorFetcher.method(:for_key_id)
    Fediverse::ActorFetcher.define_singleton_method(:for_key_id) { |key_id| fetched << key_id && nil }
  end

  teardown do
    original = @original_fetch
    Fediverse::ActorFetcher.define_singleton_method(:for_key_id) { |*args| original.call(*args) }
  end

  def deliver(tamper:)
    body = { "type" => "Follow", "actor" => @actor_uri, "object" => "https://brgen.no/users/kari" }.to_json
    headers = Fediverse::Signature.sign(key: @key, key_id: "#{@actor_uri}#main-key", method: :post,
                                        url: "https://brgen.no/inbox", body:)
    host! "brgen.no"
    post "/inbox", params: body, headers: tamper.call(headers).merge("CONTENT_TYPE" => "application/activity+json")
  end

  test "a stale signature is refused without fetching the sender's actor" do
    deliver(tamper: ->(headers) { headers.merge("Date" => 1.hour.ago.httpdate) })

    assert_response :unauthorized
    assert_empty @fetched
  end

  test "a body that does not match its digest is refused without a fetch" do
    deliver(tamper: ->(headers) { headers.merge("Digest" => "SHA-256=#{Base64.strict_encode64('x' * 32)}") })

    assert_response :unauthorized
    assert_empty @fetched
  end
end
