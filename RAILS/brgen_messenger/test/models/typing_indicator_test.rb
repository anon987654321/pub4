# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

class TypingIndicatorTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = User.strict_loading(false).create!(
      email_address: "typing@brgen.no",
      password: "password123",
      city: @city
    )
    @conversation = Conversation.create!(conversation_type: "direct")
    ConversationParticipant.create!(conversation: @conversation, user: @user)
  end

  test "active scope uses Time.current in the configured zone" do
    Time.use_zone("Europe/Oslo") do
      travel_to Time.zone.parse("2026-07-09 12:00:00") do
        fresh = TypingIndicator.create!(
          conversation: @conversation,
          user: @user,
          expires_at: 1.minute.from_now
        )
        stale = TypingIndicator.create!(
          conversation: @conversation,
          user: User.strict_loading(false).create!(
            email_address: "typing-stale@brgen.no",
            password: "password123",
            city: @city
          ),
          expires_at: 1.minute.ago
        )

        active_ids = TypingIndicator.active.pluck(:id)
        assert_includes active_ids, fresh.id
        assert_not_includes active_ids, stale.id
      end
    end
  end
  # The partner is who the line is for. The broadcast used to leave the typer
  # out of a render everyone receives, so the partner read nothing, or " skriver".
  test "set! tells the other participant who is typing and keeps the typer off their own line" do
    partner = User.strict_loading(false).create!(
      email_address: "typing-partner@brgen.no", password: "password123", city: @city
    )
    ConversationParticipant.create!(conversation: @conversation, user: partner)
    @user.update_columns(display_name: "Kari Skriv")

    streams = capture_turbo_stream_broadcasts(@conversation) do
      TypingIndicator.set!(conversation: @conversation, user: @user)
    end
    stream = streams.find { |broadcast| broadcast["target"] == "typing-indicator" }

    assert_equal "update", stream["action"]
    general = stream.at_css("template span[data-typing-target=line]:not([data-except])")
    own = stream.at_css("template span[data-except=\"#{@user.id}\"]")
    assert_equal I18n.t("messages.typing_one", name: "Kari Skriv", locale: :nb), general.text
    assert_equal "", own.text
  end

  test "nobody typing renders no text" do
    html = ApplicationController.render(partial: "typing_indicators/indicator", locals: { conversation: @conversation })

    assert_equal "", Nokogiri::HTML.fragment(html).text.strip
  end
end
