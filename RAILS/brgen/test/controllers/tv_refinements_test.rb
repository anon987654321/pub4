# frozen_string_literal: true

require "test_helper"

# TV pages and writes that were wrong in ways a happy-path test does not see:
# comments onto drafts, strict-loading reads, page-capped counts, per-row
# queries and the live chat line.
class TvRefinementsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = member("tvr_owner")
    @viewer = member("tvr_viewer")
    ActsAsTenant.current_tenant = @city
    @channel = Tv::Channel.create!(user: @owner, name: "Brygge-TV", slug: "kanal-#{SecureRandom.hex(4)}")
    @video = video_on(@channel, "Bryggen i tåke")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def member(handle)
    User.strict_loading(false).create!(
      email_address: "#{handle}@brgen.no", password: "password123", username: handle, guest: false
    )
  end

  def video_on(channel, title, status: "published")
    Tv::Video.create!(channel:, user: channel.user_id == @owner.id ? @owner : @viewer, title:, status:,
                      published_at: Time.current, duration_seconds: 90)
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! "tv.brgen.no"
  end

  def queries_matching(pattern)
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].match?(pattern) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  test "a draft takes no comments and no notes" do
    draft = video_on(@channel, "Kladd", status: "ready")
    sign_in_as(@viewer)

    assert_no_difference -> { Tv::Comment.count + Tv::VideoNote.count } do
      post tv.video_comments_path(draft), params: { tv_comment: { body: "Heia" } }
      assert_response :not_found
      post tv.video_video_notes_path(draft), params: { video_note: { body: "Fin", timestamp: 3 } }
      assert_response :not_found
    end
  end

  test "a show lists episodes that carry a video, read in one preload" do
    show = Tv::Show.create!(channel: @channel, title: "Byliv", description: "Om byen", slug: "byliv", published: true)
    Tv::Episode.create!(show:, number: 1, title: "Første", video: @video)
    Tv::Episode.create!(show:, number: 2, title: "Andre", video: video_on(@channel, "Andre"))
    host! "tv.brgen.no"

    lazy = queries_matching(/FROM "tv_videos" WHERE "tv_videos"."id" = /) { get tv.channel_show_path(@channel, show) }
    assert_response :success
    assert_equal 0, lazy
    assert_select "a[href=?]", tv.episode_channel_show_path(@channel, show, number: 1)
  end

  test "a video page shows its comments with their authors" do
    Tv::Comment.create!(video: @video, user: @viewer, body: "Nydelig lys")
    host! "tv.brgen.no"

    reads = queries_matching(/FROM "tv_comments"/) { get tv.video_path(@video) }
    assert_response :success
    assert_equal 1, reads, "comments come off the preload, not a second ordered query"
    assert_match "Nydelig lys", response.body
    assert_match @viewer.display_name, response.body
  end

  test "a channel counts all its videos, not one page of them" do
    25.times { |i| video_on(@channel, "Klipp #{i}") }
    host! "tv.brgen.no"

    get tv.channel_path(@channel)
    assert_response :success
    assert_match I18n.t("tv.videos_shown", count: 26), response.body
  end

  test "watching a video adds to its channel's total views" do
    host! "tv.brgen.no"

    assert_difference -> { @channel.reload.total_views.to_i }, 1 do
      get tv.video_path(@video)
    end
  end

  test "the channel list reads live state in one query" do
    2.times { |i| Tv::Channel.create!(user: @owner, name: "Kanal #{i}", slug: "kanal-#{SecureRandom.hex(4)}") }
    Tv::Broadcast.create!(channel: @channel, user: @owner, title: "Nå", status: "live")
    host! "tv.brgen.no"

    reads = queries_matching(/tv_broadcasts/) { get tv.channels_path }
    assert_response :success
    assert_equal 1, reads
    assert_select ".live-badge", 1
  end

  test "a live stream names its status in the locale" do
    stream = Tv::LiveStream.create!(user: @owner, channel: @channel, title: "Kveld", status: "scheduled")
    host! "tv.brgen.no"

    get tv.live_stream_path(stream)
    assert_select ".live-badge", text: I18n.t("tv.live_streams.status.scheduled")
  end

  test "the owner goes live and ends the stream from its page, and only the owner sees the key" do
    stream = Tv::LiveStream.create!(user: @owner, channel: @channel, title: "Kveld", status: "scheduled",
                                    stream_key: SecureRandom.hex(16))
    sign_in_as(@viewer)
    get tv.live_stream_path(stream)
    assert_select "form[action=?]", tv.go_live_live_stream_path(stream), count: 0
    refute_includes response.body, stream.stream_key

    sign_in_as(@owner)
    get tv.live_stream_path(stream)
    assert_select ".live-stream-key", text: stream.stream_key
    assert_select "form[action=?] input[name=_method][value=patch]", tv.go_live_live_stream_path(stream)

    patch tv.go_live_live_stream_path(stream)
    assert_equal "live", stream.reload.status
    get tv.live_stream_path(stream)
    assert_select "form[action=?]", tv.end_live_live_stream_path(stream)
    assert_select "form[action=?]", tv.go_live_live_stream_path(stream), count: 0
  end

  test "a chat line names its author and time, and the composer resets" do
    stream = Tv::LiveStream.create!(user: @owner, channel: @channel, title: "Kveld", status: "live")
    sign_in_as(@viewer)

    post tv.live_stream_stream_chats_path(stream), params: { stream_chat: { message: "Hei alle" } }, as: :turbo_stream
    assert_response :success
    assert_match %(action="replace" target="tv-live-stream-#{stream.id}-composer"), response.body

    get tv.live_stream_path(stream)
    assert_select "#tv-live-stream-#{stream.id}-entries[role=log][aria-live=polite]"
    assert_select "#tv-live-stream-#{stream.id}-entries p", text: /#{Regexp.escape(@viewer.display_name)}.*Hei alle/m
    assert_select "#tv-live-stream-#{stream.id}-entries p time[datetime]"
  end

  test "stream chat refuses a second line inside the slow-mode window" do
    stream = Tv::LiveStream.create!(user: @owner, channel: @channel, title: "Kveld", status: "live")
    sign_in_as(@viewer)

    assert_difference -> { Tv::StreamChat.count }, 1 do
      post tv.live_stream_stream_chats_path(stream), params: { stream_chat: { message: "Én" } }
      post tv.live_stream_stream_chats_path(stream), params: { stream_chat: { message: "To" } }
    end
    assert_equal I18n.t("tv.stream_chat_slow_mode"), flash[:alert]
  end

  test "the feed carries both sound labels for its buttons" do
    host! "tv.brgen.no"

    get tv.feed_path
    assert_select "[data-tv-feed-sound-off-label-value=?]", I18n.t("tv.feed.sound_off")
  end

  test "subscribing swaps the button and the count in place, and unsubscribing undoes both" do
    sign_in_as(@viewer)
    button = ActionView::RecordIdentifier.dom_id(@channel, :subscribe_button)
    count = ActionView::RecordIdentifier.dom_id(@channel, :subscribers)

    post tv.subscribe_channel_path(@channel), as: :turbo_stream
    assert_response :success
    assert_select "turbo-stream[action=replace][target=?]", button
    assert_select "turbo-stream[target=?] template", count, text: I18n.t("tv.subscribers", count: 1)
    assert_equal 1, @channel.reload.subscribers_count

    delete tv.unsubscribe_channel_path(@channel), as: :turbo_stream
    assert_select "turbo-stream[target=?] template", count, text: I18n.t("tv.subscribers", count: 0)
    assert_equal 0, @channel.reload.subscribers_count.to_i

    post tv.subscribe_channel_path(@channel)
    assert_redirected_to tv.channel_path(@channel)
    get tv.channel_path(@channel)
    assert_select "##{button} form[action=?]", tv.unsubscribe_channel_path(@channel)
    assert_select "li##{count}", text: I18n.t("tv.subscribers", count: 1)
  end
end
