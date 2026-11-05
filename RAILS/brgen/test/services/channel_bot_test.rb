# frozen_string_literal: true

require "test_helper"

# What a room's bots answer, and what they are shown before answering.
class ChannelBotTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @channel = Conversation.find_or_create_channel("brgen", city: @city)
    @human = User.create!(email_address: "bot-test-#{SecureRandom.hex(4)}@brgen.no", password: "password123")
    @channel.join!(@human)
    @bots = ActsAsTenant.without_tenant { @channel.participants.where(bot: true).to_a }
  end

  teardown do
    Rails.cache.clear
    ActsAsTenant.current_tenant = nil
  end

  test "a room volunteers one unprompted reply per cooldown window" do
    question = Message.new(sender: @human, content: "anyone know a good cafe?")

    assert ChannelBot.bot_for_message(@channel, question, @bots), "the first question gets a bot"
    assert_nil ChannelBot.bot_for_message(@channel, question, @bots),
               "a second question inside the window must not trigger another reply"

    travel ChannelBot::VOLUNTEER_COOLDOWN + 1.second do
      assert ChannelBot.bot_for_message(@channel, question, @bots), "the window reopens"
    end
  end

  test "a bot named in the message still answers inside the cooldown" do
    ChannelBot.bot_for_message(@channel, Message.new(sender: @human, content: "hello?"), @bots)

    addressed = ChannelBot.bot_for_message(@channel, Message.new(sender: @human, content: "@echo you there"), @bots)
    assert_equal "echo", addressed&.username
  end

  test "unsent and expired lines never reach the prompt" do
    kept = @channel.messages.create!(sender: @human, message_type: "text", content: "kept line")
    unsent = @channel.messages.create!(sender: @human, message_type: "text", content: "unsent line")
    expired = @channel.messages.create!(sender: @human, message_type: "text", content: "expired line")
    unsent.update_column(:deleted_at, Time.current)
    expired.update_column(:expires_at, 1.minute.ago)

    transcript = ChannelBot.transcript(@channel)
    assert_includes transcript, kept.content
    assert_not_includes transcript, unsent.content
    assert_not_includes transcript, expired.content
    assert_equal [ kept.id ], ChannelBot.context_messages(@channel).map(&:id) & [ kept.id, unsent.id, expired.id ]
  end
end

# A room speaks its city's language: the prompt asks for it, and the offline
# fallback answers in it, so brgen.no's rooms are not answered in English.
class ChannelBotLanguageTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
    Brgen::CitySeed.sync! if City.table_exists?
  end

  teardown do
    Rails.cache.clear
    ActsAsTenant.current_tenant = nil
  end

  test "a brgen.no room is prompted and answered offline in Norwegian" do
    channel = Conversation.find_or_create_channel("brgen", city: City.find_by!(domain: "brgen.no"))
    echo = ChannelBot.bot_for("echo")

    assert_equal :nb, ChannelBot.room_locale(channel)
    assert_includes ChannelBot.prompt_for(ChannelBot::PERSONAS.fetch("echo"), channel), "Norwegian Bokmål"
    assert_includes ChannelBot.master_context_for(channel), "Norwegian Bokmål"

    I18n.with_locale(:en) do
      Shared::Llm.stub(:new, ->(**) { raise "offline" }) do
        line = ChannelBot.draft(echo, channel, Message.new(content: "hei?"))
        assert_includes I18n.t("channels.bots.echo", locale: :nb), line
      end
    end
  end

  test "every persona has offline lines in both shipped locales" do
    ChannelBot::PERSONAS.each_key do |handle|
      %i[nb en].each do |locale|
        assert_operator ChannelBot.canned_lines(handle, locale).size, :>=, 1, "#{handle} has no #{locale} lines"
      end
    end
  end
end
