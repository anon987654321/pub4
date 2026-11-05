# frozen_string_literal: true

require "test_helper"

# A visitor's soft guest is not saved until it writes something, so it has no
# id. The layout subscribed it to "nearby_alerts_" and "brgen:matches:" anyway:
# streams nothing broadcasts to, which the cable refuses to a connection with
# nobody behind it, so every page carried a stream source that never connected.
class UnsavedGuestStreamsTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    host! "brgen.no"
  end

  test "a page for an unsaved guest names no stream after a missing id" do
    get new_session_path

    assert_response :success
    names = css_select("turbo-cable-stream-source").map do |source|
      Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"])
    end
    assert_empty names.grep(/(?:_|:)\z/), "streams named for a user with no id: #{names.inspect}"
  end
end
