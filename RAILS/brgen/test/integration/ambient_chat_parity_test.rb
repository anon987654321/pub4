# frozen_string_literal: true

require "test_helper"

# Every brgen surface offers the same chat. The verticals are mountable engines
# and an engine's url_helpers do not carry the host application's routes, so
# `_nearby_chat_widget`'s `respond_to?(:nearby_widget_path)` was false inside
# marketplace, dating, tv, playlist and takeaway. On those five the shared
# widget silently fell through to its "no chat on this app" branch and offered a
# link to another domain — on the same application, with the same Conversation
# model, pointing at the room that already worked on the front page.
#
# It survived because the fallback looks deliberate. Nothing 500s, nothing logs,
# and the widget renders a tidy call-to-action; only a human tapping the bar on
# markedsplass and getting an off-site link would notice. maps and messenger are
# not engines, which is exactly why those two always worked and hid the pattern.
class AmbientChatParityTest < ActionDispatch::IntegrationTest
  VERTICAL_HOSTS = %w[
    markedsplass.brgen.no
    dating.brgen.no
    tv.brgen.no
    playlist.brgen.no
    takeaway.brgen.no
    maps.brgen.no
    messenger.brgen.no
  ].freeze

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
  end

  test "every brgen vertical renders the real chat frame, not the off-site handoff" do
    ([ "brgen.no" ] + VERTICAL_HOSTS).each do |host|
      host! host
      get "/"

      assert_includes 200..399, @response.status,
                      "#{host} returned #{@response.status}"

      # count/message form: with a `?` substitution the third argument is the
      # equality test, not the message, so a message there asserts the element's
      # TEXT equals it.
      assert_select %(turbo-frame#nearby-chat-widget-frame[src="/nearby/widget"]),
                    { count: 1 },
                    "#{host} must load the shared chat room, not a handoff"
      assert_no_match %r{https://brgen\.no/channels/brgen}, @response.body,
                      "#{host} is brgen — it must not link out to itself for chat"
    end
  end

  # The handoff is still correct where there is genuinely no room to join:
  # amber and bsdports have no Conversation model. Guarding the helper directly
  # because those apps are not booted by this suite.
  test "the frame path is nil when the app has no nearby route" do
    helper = Object.new.extend(Shared::UiHelper)

    assert_nil helper.ambient_chat_frame_path,
               "an app with neither route must fall back rather than raise"
  end
end
