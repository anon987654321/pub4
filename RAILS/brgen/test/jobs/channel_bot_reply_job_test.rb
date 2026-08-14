# frozen_string_literal: true

require "test_helper"

# The bots never replied, for two reasons stacked on top of each other.
#
# No Solid Queue worker runs on vm23, so ChannelBotReplyJob had never executed —
# `perform_later` means never here. The first time anything drained the queue,
# on 2026-08-14, the job raised on its first line and gave up after three tries:
#
#   ActiveRecord::StrictLoadingViolationError: `Message` is marked for
#   strict_loading. The Conversation association named `:conversation` cannot be
#   lazily loaded.
#
# ApplicationRecord sets strict_loading_by_default = true in every environment,
# and ChannelBot.reply_to opens with `message.conversation`. So even a working
# queue would have produced silence. The same shape is recorded in
# brgen_anonymous_chat_breakages — rooms 500'd for weeks on strict_loading.
#
# These tests run the job for real rather than asserting on its source, because
# the whole failure was that nothing had ever run it. Loading `conversation`
# alone is not obviously sufficient — reply_to goes on to read
# channel.participants — so the assertion is that perform does not raise, which
# is the only claim that covers whatever it touches next.
class ChannelBotReplyJobTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @channel = Conversation.find_or_create_channel("brgen", city: @city)
    @human = User.create!(email_address: "chatter-#{SecureRandom.hex(4)}@brgen.no", password: "password123")
    @channel.join!(@human)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "performing the job does not raise on a strict-loaded message" do
    message = @channel.messages.create!(sender: @human, message_type: "text", content: "@master hei, er du der?")

    assert_nothing_raised do
      ChannelBotReplyJob.new.perform(message.id)
    end
  end

  # Addressing a bot by handle is the one path that always answers, so it is the
  # one that can assert an outcome rather than the absence of an exception.
  test "a message addressing a bot gets a reply from that bot" do
    before = @channel.messages.count
    message = @channel.messages.create!(sender: @human, message_type: "text", content: "@master hva skjer i kveld?")

    ChannelBotReplyJob.new.perform(message.id)

    assert_operator @channel.messages.reload.count, :>, before + 1,
                    "the bot's reply should be in the room alongside the human's line"
    assert @channel.messages.order(:created_at).last.sender.bot?
  end

  test "a missing message is a no-op rather than an error" do
    assert_nothing_raised { ChannelBotReplyJob.new.perform(-1) }
  end
end
