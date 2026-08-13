# frozen_string_literal: true

require "test_helper"

# The inbox is where an unverified string becomes an action. Everything here is
# a way an attacker gets to act as someone else if a check is missing.
class FediverseInboxTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "inbox_kari@brgen.no", password: "password123",
      username: "kari", guest: false, city: @city
    )
    @key = OpenSSL::PKey::RSA.new(2048)
    @actor_uri = "https://remote.example/users/ola"
    @actor = FediActor.create!(
      uri: @actor_uri,
      inbox_url: "https://remote.example/users/ola/inbox",
      username: "ola", domain: "remote.example",
      public_key_pem: @key.public_key.to_pem,
      last_fetched_at: Time.current
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def follow_activity(id: "https://remote.example/activities/#{SecureRandom.uuid}")
    {
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => id,
      "type" => "Follow",
      "actor" => @actor_uri,
      "object" => "https://brgen.no/users/kari"
    }
  end

  def deliver(activity, key: @key, key_id: "#{@actor_uri}#main-key", path: "/inbox", tamper: nil)
    body = activity.to_json
    headers = Fediverse::Signature.sign(
      key: key, key_id: key_id, method: :post, url: "https://brgen.no#{path}", body: body
    )
    headers = tamper.call(headers) if tamper
    host! "brgen.no"
    post path, params: body, headers: headers.merge("CONTENT_TYPE" => "application/activity+json")
  end

  test "a signed Follow is accepted and recorded" do
    assert_difference -> { FediFollow.count }, 1 do
      deliver(follow_activity)
    end
    assert_response :accepted

    follow = FediFollow.last
    assert_equal @user.id, follow.user_id
    assert_equal "accepted", follow.state
  end

  test "an unsigned Follow is refused" do
    host! "brgen.no"

    assert_no_difference -> { FediFollow.count } do
      post "/inbox", params: follow_activity.to_json,
           headers: { "CONTENT_TYPE" => "application/activity+json" }
    end
    assert_response :unauthorized
  end

  test "a Follow signed with the wrong key is refused" do
    other = OpenSSL::PKey::RSA.new(2048)

    assert_no_difference -> { FediFollow.count } do
      deliver(follow_activity, key: other)
    end
    assert_response :unauthorized
  end

  # The one that matters most: a valid signature from one actor must not
  # authorise an activity attributed to another, or every account is forgeable
  # by anyone with an account anywhere.
  test "a validly signed activity claiming to be someone else is refused" do
    impersonation = follow_activity.merge("actor" => "https://remote.example/users/somebody-else")

    assert_no_difference -> { FediFollow.count } do
      deliver(impersonation)
    end
    assert_response :forbidden
  end

  test "a body swapped after signing is refused" do
    body = follow_activity.to_json
    headers = Fediverse::Signature.sign(
      key: @key, key_id: "#{@actor_uri}#main-key", method: :post, url: "https://brgen.no/inbox", body: body
    )
    host! "brgen.no"

    assert_no_difference -> { FediFollow.count } do
      post "/inbox", params: follow_activity.merge("type" => "Delete").to_json,
           headers: headers.merge("CONTENT_TYPE" => "application/activity+json")
    end
    assert_response :unauthorized
  end

  # Delivery retries on any non-2xx and several implementations retry
  # optimistically, so the same activity arriving twice is routine.
  test "the same activity delivered twice is processed once" do
    activity = follow_activity

    assert_difference -> { FediFollow.count }, 1 do
      deliver(activity)
      deliver(activity)
    end
    assert_equal 1, FediActivity.where(uri: activity["id"]).count
  end

  test "an Undo Follow removes the follow" do
    deliver(follow_activity)
    assert_equal 1, FediFollow.count

    undo = {
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => "https://remote.example/activities/#{SecureRandom.uuid}",
      "type" => "Undo",
      "actor" => @actor_uri,
      "object" => { "type" => "Follow", "actor" => @actor_uri, "object" => "https://brgen.no/users/kari" }
    }

    assert_difference -> { FediFollow.count }, -1 do
      deliver(undo)
    end
  end

  test "a Follow for an account in another city is not resolved here" do
    other = follow_activity.merge("object" => "https://oshlo.no/users/kari")

    assert_no_difference -> { FediFollow.count } do
      deliver(other)
    end
    assert_response :accepted, "handled and ignored, not an error"
  end

  test "a Follow for an unknown account is ignored" do
    unknown = follow_activity.merge("object" => "https://brgen.no/users/nobody")

    assert_no_difference -> { FediFollow.count } do
      deliver(unknown)
    end
  end

  test "a malformed body is refused before anything is parsed into action" do
    host! "brgen.no"
    post "/inbox", params: "not json at all",
         headers: { "CONTENT_TYPE" => "application/activity+json" }

    assert_response :bad_request
  end

  test "an oversized body is refused" do
    host! "brgen.no"
    post "/inbox", params: "x" * (Fediverse::InboxesController::MAX_BODY + 1),
         headers: { "CONTENT_TYPE" => "application/activity+json" }

    assert_response :content_too_large
  end

  test "the per-user inbox works the same as the shared one" do
    assert_difference -> { FediFollow.count }, 1 do
      deliver(follow_activity, path: "/users/kari/inbox")
    end
    assert_response :accepted
  end
end
