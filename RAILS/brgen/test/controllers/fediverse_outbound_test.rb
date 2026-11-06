# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The outbound half: following somebody, telling the fediverse about an edit,
# and refusing an instance.
class FediverseOutboundTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "out_kari@brgen.no", password: "password123", username: "outkari", guest: false, city: @city
    )
    @key = OpenSSL::PKey::RSA.new(2048)
    @actor_uri = "https://remote.example/users/ola"
    @actor = FediActor.create!(
      uri: @actor_uri, inbox_url: "https://remote.example/users/ola/inbox",
      username: "ola", domain: "remote.example",
      public_key_pem: @key.public_key.to_pem, last_fetched_at: Time.current
    )
    ActsAsTenant.current_tenant = @city
    Rails.cache.clear
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Rails.cache.clear
  end

  def sign_in
    host! "brgen.no"
    post session_path, params: { email_address: @user.email_address, password: "password123" }
  end

  # The row is written before the Follow is sent and stays pending until an
  # Accept arrives: "asked and not answered" is a state a fire-and-forget POST
  # cannot give you.
  test "following a remote account records a pending follow and enqueues delivery" do
    sign_in

    assert_difference -> { FediFollow.outbound.count }, 1 do
      assert_enqueued_with(job: Fediverse::DeliveryJob) do
        post fediverse_follows_path, params: { uri: @actor_uri }
      end
    end
    follow = FediFollow.outbound.last
    assert_equal "pending", follow.state
    assert follow.activity_uri.present?, "the Follow id has to be kept — an Accept names it"
  end

  def webfinger_for(handle_host, href)
    lambda do |url|
      next unless url.start_with?("https://#{handle_host}/.well-known/webfinger?")

      profile = { "rel" => "http://webfinger.net/rel/profile-page", "type" => "text/html",
                  "href" => "https://#{handle_host}/@ola" }
      actor = { "rel" => "self", "type" => "application/activity+json", "href" => href }
      { "subject" => "acct:ola@#{handle_host}", "links" => [ profile, actor ] }
    end
  end

  test "a handle is resolved through WebFinger and followed like its actor URL" do
    sign_in

    Fediverse::Client.stub(:get_json, webfinger_for("remote.example", @actor_uri)) do
      assert_difference -> { FediFollow.outbound.where(fedi_actor: @actor).count }, 1 do
        post fediverse_follows_path, params: { uri: "@ola@remote.example" }
      end
    end
    assert_redirected_to fediverse_follows_path
    assert_equal I18n.t("flash.fediverse.follow_sent"), flash[:notice]
  end

  test "a handle WebFinger cannot resolve is reported as not found" do
    sign_in

    Fediverse::Client.stub(:get_json, ->(_url) { { "links" => [] } }) do
      assert_no_difference -> { FediFollow.outbound.count } do
        post fediverse_follows_path, params: { uri: "ola@remote.example" }
      end
    end
    assert_equal I18n.t("flash.fediverse.follow_not_found"), flash[:alert]
  end

  test "a handle on a blocked instance is refused before anything is fetched" do
    FediBlock.create!(domain: "remote.example")
    sign_in

    Fediverse::Client.stub(:get_json, ->(url) { flunk "fetched #{url}" }) do
      post fediverse_follows_path, params: { uri: "@ola@remote.example" }
    end
    assert_equal I18n.t("flash.fediverse.follow_blocked"), flash[:alert]
  end

  test "the remote Accept answers our own follow, and only ours" do
    follow = FediFollow.create!(user: @user, fedi_actor: @actor, direction: "outbound",
                                state: "pending", activity_uri: "https://brgen.no/users/outkari#follows/abc")
    other_actor = FediActor.create!(uri: "https://elsewhere.example/users/per",
                                    inbox_url: "https://elsewhere.example/users/per/inbox",
                                    username: "per", domain: "elsewhere.example",
                                    public_key_pem: @key.public_key.to_pem, last_fetched_at: Time.current)

    assert_equal :unknown_target, process_accept(actor: other_actor, object: follow.activity_uri)
    assert_equal "pending", follow.reload.state

    assert_equal :accepted, process_accept(actor: @actor, object: follow.activity_uri)
    assert_equal "accepted", follow.reload.state
  end

  # A refusal is an answer. Left pending it reads as "still waiting" for good.
  test "a Reject removes the follow" do
    follow = FediFollow.create!(user: @user, fedi_actor: @actor, direction: "outbound",
                                state: "pending", activity_uri: "https://brgen.no/users/outkari#follows/def")

    activity = { "id" => "https://remote.example/activities/#{SecureRandom.uuid}", "type" => "Reject",
                 "actor" => @actor_uri, "object" => follow.activity_uri }
    assert_equal :rejected, Fediverse::InboxProcessor.new(activity, @actor).call
    assert_not FediFollow.exists?(follow.id)
  end

  test "a blocked instance cannot be followed" do
    FediBlock.create!(domain: "remote.example")
    sign_in

    assert_no_difference -> { FediFollow.outbound.count } do
      post fediverse_follows_path, params: { uri: @actor_uri }
    end
  end

  # A block that only works on the way in is a block that leaks on the way out.
  test "delivery to a blocked instance does not happen" do
    FediBlock.create!(domain: "remote.example")

    assert_no_enqueued_jobs only: Fediverse::DeliveryJob do
      Fediverse::DeliveryJob.perform_now(inbox_url: @actor.inbox_url, user_id: @user.id, payload: "{}")
    end
  end

  test "an edit is federated, and a counter touching the row is not" do
    post_record = Post.create!(user: @user, title: "Sol på Fløyen", content: "Første utkast")

    assert_enqueued_with(job: Fediverse::DistributeJob) do
      post_record.update!(content: "Andre utkast")
    end

    assert_no_enqueued_jobs only: Fediverse::DistributeJob do
      post_record.update_columns(comments_count: 3, updated_at: Time.current)
      post_record.touch
    end
  end

  test "the Update carries the edited note" do
    post_record = Post.create!(user: @user, title: "Regn i Bergen", content: "Igjen")
    payload = Fediverse::Serializer.update(post_record)

    assert_equal "Update", payload["type"]
    assert_equal post_record.user.actor_uri, payload["actor"]
    assert_includes payload.dig("object", "content").to_s, "Igjen"
  end

  def process_accept(actor:, object:)
    activity = { "id" => "https://#{actor.domain}/activities/#{SecureRandom.uuid}", "type" => "Accept",
                 "actor" => actor.uri, "object" => object }
    Fediverse::InboxProcessor.new(activity, actor).call
  end
end
