# frozen_string_literal: true

require "test_helper"

# GET /conversations/new is the people picker: "start a conversation" without
# knowing anybody's exact username. The action called apply_live_search and
# finish_live_search without including Shared::LiveSearchable, so the page
# answered 500 for everybody; found by the signed-in flow gate
# (MASTER/gates/data/flows.yml, brgen_messenger_send_and_read).
class ConversationPeoplePickerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @me = create_user("picker_me")
    @other = create_user("picker_other")
  end

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  test "the picker lists people the reader can message and opens a thread with a button" do
    host! "brgen.no"
    post session_path, params: { email_address: @me.email_address, password: "password123" }

    get new_conversation_path

    assert_response :success
    assert_includes response.body, user_conversations_path(@other)
    refute_includes response.body, user_conversations_path(@me), "nobody is offered a conversation with themselves"
  end

  test "a query narrows the list" do
    host! "brgen.no"
    post session_path, params: { email_address: @me.email_address, password: "password123" }

    get new_conversation_path(q: "picker_other")

    assert_response :success
    assert_includes response.body, user_conversations_path(@other)
  end
end
