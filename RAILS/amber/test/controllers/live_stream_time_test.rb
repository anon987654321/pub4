# frozen_string_literal: true

require "test_helper"

# The list printed l(time, :long), which nb defines as date-only, and the
# show page printed :short, which is time-only, so no page said when a
# session starts. The show page also printed the raw status ("scheduled").
class LiveStreamTimeTest < ActionDispatch::IntegrationTest
  setup do
    email = "host-#{SecureRandom.hex(4)}@amber.test"
    @host = User.strict_loading(false).create!(email_address: email, password: "password123")
    @stream = LiveStream.create!(user: @host, title: "Høstgarderobe", status: "scheduled",
                                 scheduled_at: Time.zone.local(2026, 11, 20, 18, 30))
    post session_path, params: { email_address: @host.email_address, password: "password123" }
  end

  test "the list and the page give the date and the time" do
    get live_streams_path(locale: "nb")
    assert_select "time[datetime=?]", @stream.scheduled_at.iso8601, text: /20\. november 2026 kl\. 18:30/

    get live_stream_path(@stream, locale: "nb")
    assert_includes response.body, "20. november 2026 kl. 18:30"
  end

  test "the page names the status in the reader's language" do
    get live_stream_path(@stream, locale: "nb")
    status = I18n.t("live_streams.status.scheduled", locale: :nb)
    assert_includes response.body, I18n.t("live_streams.style_session", status:, locale: :nb)
  end
end
