# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# A viewer waiting on a scheduled stream: the page says it has not started,
# and going live or ending replaces that line for everyone on the page.
class TvLiveStatusTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "tvl_#{SecureRandom.hex(3)}@brgen.no",
                                                password: "password123", username: "tvl_#{SecureRandom.hex(3)}",
                                                guest: false)
    channel = Tv::Channel.create!(user: @owner, name: "Direkte-TV", slug: "direkte-#{SecureRandom.hex(4)}")
    @stream = Tv::LiveStream.create!(user: @owner, channel:, title: "Kveldssending", status: "scheduled")
    host! "tv.brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def status_line = "#tv-live-stream-#{@stream.id}-status[role=status]"

  test "a scheduled stream's page says it has not started and listens for the change" do
    get tv.live_stream_path(@stream)

    assert_select status_line, text: /#{Regexp.escape(I18n.t("tv.live_streams.status_line.scheduled"))}/
    names = css_select("turbo-cable-stream-source").map { |source| source["signed-stream-name"] }
    assert_includes names, Turbo::StreamsChannel.signed_stream_name(@stream.status_stream)
  end

  test "going live and ending each replace the status line for the watchers" do
    live = capture_turbo_stream_broadcasts(@stream.status_stream) { @stream.go_live! }
    assert_equal "replace", live.sole["action"]
    assert_equal "tv-live-stream-#{@stream.id}-status", live.sole["target"]
    assert_includes live.sole.to_html, I18n.t("tv.live_streams.status_line.live")

    ended = capture_turbo_stream_broadcasts(@stream.status_stream) { @stream.end_live! }
    assert_includes ended.sole.to_html, I18n.t("tv.live_streams.status_line.ended")
  end
end
