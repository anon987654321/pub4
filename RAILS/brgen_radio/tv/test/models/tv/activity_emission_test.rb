# frozen_string_literal: true

require "test_helper"

# The Tv activity emitters all passed `actor: user` — a lazy belongs_to read.
# Every model here is strict_loading by default (shared ApplicationRecord) and
# production raises on a violation rather than logging, so a broadcast, stream or
# video that a controller loaded by id had nothing preloaded and the emitter
# raised *after* update! had already committed the state change: the broadcast
# went live, the activity event was never recorded, and the caller saw a 500.
#
# Loading each record with a bare find_by is the point of these tests.
class Tv::ActivityEmissionTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "tv_owner@brgen.no", password: "password123", city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def channel
    @channel ||= Tv::Channel.create!(
      user: @owner, name: "Vestland Nyheter", slug: "vestland-nyheter-#{SecureRandom.hex(4)}"
    )
  end

  test "go_live! and end_live! on a freshly-found broadcast emit activity" do
    ActsAsTenant.with_tenant(@city) do
      created = Tv::Broadcast.create!(channel: channel, user: @owner, title: "Live: Bybanen", status: "scheduled")

      bare = Tv::Broadcast.find_by(id: created.id)
      refute bare.association(:user).loaded?, "guard: user must NOT be preloaded or this proves nothing"

      bare.go_live!
      assert_equal "live", created.reload.status

      Tv::Broadcast.find_by(id: created.id).end_live!
      assert_equal "ended", created.reload.status
    end
  end

  test "go_live! and end_live! on a freshly-found live stream emit activity" do
    ActsAsTenant.with_tenant(@city) do
      created = Tv::LiveStream.create!(user: @owner, channel: channel, title: "Ulriken direkte")

      Tv::LiveStream.find_by(id: created.id).go_live!
      assert_equal "live", created.reload.status

      Tv::LiveStream.find_by(id: created.id).end_live!
      assert_equal "ended", created.reload.status
    end
  end

  test "publishing a freshly-found video emits VideoPublished" do
    ActsAsTenant.with_tenant(@city) do
      created = Tv::Video.create!(
        user: @owner, channel: channel, title: "Fisketorget tidlig morgen", status: "ready"
      )

      bare = Tv::Video.find_by(id: created.id)
      refute bare.association(:user).loaded?, "guard: user must NOT be preloaded or this proves nothing"

      # after_update_commit :record_video_published fires here.
      bare.update!(status: "published", published_at: Time.current)

      assert_equal "published", created.reload.status
    end
  end
end
