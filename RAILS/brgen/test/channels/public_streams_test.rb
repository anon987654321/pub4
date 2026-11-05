# frozen_string_literal: true

require "test_helper"

# A signed-out visitor holds a connection with nobody behind it. It may read the
# city's front page and a post's page live, and nothing that is somebody's.
class PublicStreamsTest < ActionCable::Channel::TestCase
  tests Turbo::StreamsChannel

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.strict_loading(false).create!(email_address: "public-streams@brgen.no",
                                               password: "password123", city: @city)
    @post = Post.create!(user: @user, city: @city, title: "Offentlig", content: "Alle kan lese")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "nobody may read the city front page" do
    assert_subscribed_as(nil, Post.city_feed_stream(@city.id))
  end

  test "nobody may read a post and its comments" do
    assert_subscribed_as(nil, @post)
    assert_subscribed_as(nil, [ @post, "comments" ])
  end

test "nobody may read the notes under a video anyone may watch" do
  video = tv_video(status: "published")

  assert_subscribed_as(nil, "tv:video:#{video.id}:notes")
end

test "nobody is refused the notes under a held or unlisted video" do
  held = tv_video(status: "published", review_held_at: Time.current)
  unlisted = tv_video(status: "unlisted")

  assert_refused_as(nil, "tv:video:#{held.id}:notes")
  assert_refused_as(nil, "tv:video:#{unlisted.id}:notes")
  assert_refused_as(nil, "tv:video:#{held.id + unlisted.id + 1000}:notes")
end

test "nobody is refused a person's notifications and inbox" do
    assert_refused_as(nil, [ @user, :notifications ])
    assert_refused_as(nil, [ @user, :inbox ])
    assert_refused_as(nil, "brgen:matches:#{@user.id}")
  end

  test "a signed-in reader still reads their own streams" do
    assert_subscribed_as(@user, [ @user, :notifications ])
  end

  test "a forged stream name is refused" do
    stub_connection(current_user: nil)
    subscribe(signed_stream_name: "brgen:feed:#{@city.id}")

    assert subscription.rejected?
  end

private

def tv_video(**attributes)
  @tv_channel ||= Tv::Channel.create!(name: "Notekanalen", slug: "notekanalen-#{SecureRandom.hex(3)}", user: @user)
  Tv::Video.create!(title: "Notat", channel: @tv_channel, user: @user, published_at: Time.current, **attributes)
end

  def assert_subscribed_as(user, streamable)
    stub_connection(current_user: user)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(streamable))

    assert subscription.confirmed?, "#{streamable.inspect} was refused"
  end

  def assert_refused_as(user, streamable)
    stub_connection(current_user: user)
    subscribe(signed_stream_name: Turbo::StreamsChannel.signed_stream_name(streamable))

    assert subscription.rejected?, "#{streamable.inspect} was served to nobody"
  end
end
