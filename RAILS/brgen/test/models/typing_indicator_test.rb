# frozen_string_literal: true

require "test_helper"

class TypingIndicatorTest < ActiveSupport::TestCase
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
end