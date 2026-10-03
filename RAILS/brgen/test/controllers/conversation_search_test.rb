# frozen_string_literal: true

require "test_helper"

class ConversationSearchTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = create_user("search_user")
    @friend = create_user("search_friend")
    @stranger = create_user("search_stranger")
    ActsAsTenant.current_tenant = @city
    @mine = Conversation.find_or_create_direct(@user, @friend)
    @theirs = Conversation.find_or_create_direct(@friend, @stranger)
    @hit = say(@mine, @friend, "Sykkelen står i bakgården")
    say(@mine, @user, "Takk for kaffen")
    @other_thread = say(@theirs, @stranger, "Sykkelen er solgt")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def say(conversation, sender, content)
    Message.create!(conversation: conversation, sender: sender, content: content, message_type: "text")
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a query finds the reader's own message" do
    sign_in_as(@user)

    get search_conversations_path(q: "sykkelen")
    assert_response :success
    assert_includes response.body, "bakgården"
  end

  # The scope is the reader's own threads. A stranger's conversation matches the
  # same word and must not appear.
  test "search cannot reach a thread the reader is not in" do
    sign_in_as(@user)

    get search_conversations_path(q: "sykkelen")
    assert_not_includes response.body, "er solgt"
  end

  # Ephemerality is a promise, not a rendering choice: a message that has
  # disappeared or been unsent must not come back through a search box.
  test "expired and unsent messages stay gone" do
    @hit.update!(expires_at: 1.minute.ago)
    unsent = say(@mine, @user, "Adressen min er Torget 1")
    unsent.unsend!

    sign_in_as(@user)
    get search_conversations_path(q: "sykkelen")
    assert_not_includes response.body, "bakgården"

    get search_conversations_path(q: "Torget")
    assert_not_includes response.body, "Torget 1"
  end

  test "conversation_id narrows the search to one thread" do
    other_mine = Conversation.find_or_create_direct(@user, @stranger)
    say(other_mine, @stranger, "Sykkelen min er blå")

    sign_in_as(@user)
    get search_conversations_path(q: "sykkelen", conversation_id: @mine.id)
    assert_includes response.body, "bakgården"
    assert_not_includes response.body, "er blå"
  end

  test "an empty query lists nothing rather than everything" do
    sign_in_as(@user)

    get search_conversations_path
    assert_response :success
    assert_not_includes response.body, "bakgården"
  end
end
