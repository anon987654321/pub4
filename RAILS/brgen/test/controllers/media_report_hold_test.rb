# frozen_string_literal: true

require "test_helper"

# Uploaded media had no report or takedown path: a tv video or hosted track
# that infringed someone's copyright stayed up until its owner removed it. A
# copyright, abuse or illegal-content report now hides it pending review.
class MediaReportHoldTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @owner = member("mrh_own")
    @viewer = member("mrh_view")

    @channel = Tv::Channel.create!(user: @owner, name: "Rett-TV", slug: "rett-#{SecureRandom.hex(4)}")
    @video = Tv::Video.create!(channel: @channel, user: @owner, title: "Lånt film", status: "published",
                               published_at: Time.current)
    @track = Playlist::Track.create!(title: "Lånt låt", artist: "Bergen", user: @owner, source_type: "direct",
                                     source_url: "https://example.com/l.mp3", privacy: "public")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "the video page offers a signed-in viewer a report with copyright chosen" do
    sign_in_as(@viewer, host: "tv.brgen.no")

    get tv.video_path(@video)

    assert_response :success
    assert_select "details.report-picker input[type=radio][name=reason][value=copyright][checked]"
  end

  test "a copyright report hides the video until a moderator dismisses it" do
    sign_in_as(@viewer, host: "tv.brgen.no")
    post main_app.reports_path, params: { target_gid: @video.to_signed_global_id.to_s, reason: "copyright" }

    assert @video.reload.review_held_at, "the reported video is still public"
    assert_not Tv::Video.publicly_visible.exists?(@video.id)
    get tv.video_path(@video)
    assert_response :not_found

    ModerationWorkflow.transition!(report: ModerationReport.find_by!(reportable: @video), status: "dismissed")
    assert_nil @video.reload.review_held_at
    assert Tv::Video.publicly_visible.exists?(@video.id)
  end

  test "a spam report does not hide the video" do
    ModerationWorkflow.report!(reporter: @viewer, target: @video, reason: "spam")

    assert_nil @video.reload.review_held_at
  end

  test "a resolved report keeps the video down" do
    report = ModerationWorkflow.report!(reporter: @viewer, target: @video, reason: "abuse")
    ModerationWorkflow.transition!(report: ModerationReport.find(report.id), status: "resolved")

    assert @video.reload.review_held_at
  end

  test "a held track is hidden from others and its owner is told why" do
    ModerationWorkflow.report!(reporter: @viewer, target: @track, reason: "copyright")

    assert_not Playlist::Track.publicly_visible.exists?(@track.id)
    sign_in_as(@viewer, host: "radio.brgen.no")
    get playlist.hosted_track_path(@track)
    assert_response :not_found

    sign_in_as(@owner, host: "radio.brgen.no")
    get playlist.hosted_track_path(@track)
    assert_response :success
    assert_select "p[role=status]", I18n.t("playlist.track_held_for_review")
  end

  test "a signed-in listener can report a hosted track" do
    sign_in_as(@viewer, host: "radio.brgen.no")

    get playlist.hosted_track_path(@track)

    assert_select "details.report-picker input[type=radio][name=reason][value=copyright][checked]"
  end

  private

  def member(handle)
    name = "#{handle}_#{SecureRandom.hex(3)}"
    User.strict_loading(false).create!(email_address: "#{name}@brgen.no", password: "password123",
                                       username: name, guest: false, city: @city)
  end

  def sign_in_as(user, host:)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
    host! host
  end
end
