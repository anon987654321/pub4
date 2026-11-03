# frozen_string_literal: true

require "test_helper"

# A thread used to end fifty messages in: the window rendered the newest page
# and nothing reached past it. These tests pin the history contract the other
# way around — every page links to the one above it through X-History-Next,
# the walk reaches the thread's first line, the pages render only what the
# reader may see, and only a participant gets a cursor at all.
class MessageHistoryTest < ActionDispatch::IntegrationTest
  PAGE = MessagesController::HISTORY_PAGE

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @reader = create_user("history_reader")
    @friend = create_user("history_friend")
    @stranger = create_user("history_stranger")
    @conversation = Conversation.find_or_create_direct(@reader, @friend)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  # created_at is written explicitly because `recent` orders on it: a loop of
  # plain creates would land inside one SQLite second and the pages would not
  # be deterministic.
  def write_history(count)
    count.times do |i|
      Message.create!(
        conversation: @conversation, sender: @friend,
        content: "line #{i}", message_type: "text",
        created_at: count.minutes.ago - ((count - i).seconds)
      )
    end
  end

  test "show marks a thread that outgrew its window with a history url" do
    write_history(PAGE + 5)
    sign_in_as(@reader)

    get conversation_path(@conversation)

    assert_response :success
    assert_select "#messages[data-conversation-log-history-url-value*='before=']"
    assert_select "#messages[data-controller~=conversation-catch-up][data-conversation-catch-up-url-value]"
    assert_select "#messages > li[role=listitem]", count: PAGE
  end

  test "show carries no history url when the thread fits the window" do
    write_history(3)
    sign_in_as(@reader)

    get conversation_path(@conversation)

    assert_response :success
    assert_select "#messages[data-conversation-log-history-url-value]", count: 0
  end

  test "the first page is the fifty above the window and names the next cursor" do
    write_history(PAGE * 2 + 5)
    sign_in_as(@reader)
    oldest_in_window = @conversation.messages.visible.recent.first(PAGE).last

    get conversation_messages_path(@conversation, before: oldest_in_window.id)

    assert_response :success
    # The page renders the fifty lines just above the window (line 5 .. 54) and
    # no further; the cursor names the oldest line it served, so the next
    # request continues at line 4 without overlap.
    assert_includes response.body, "line #{PAGE + 4}"
    refute_includes response.body, "line #{PAGE + 5}"
    refute_includes response.body, "line 0"
    # The oldest line the page served is "line 5"; the cursor names it, so the
    # next request continues at line 4 rather than repeating it.
    assert_equal conversation_messages_path(@conversation, before: @conversation.messages.visible.find_by!(content: "line 5").id),
                 response.headers["X-History-Next"]
  end

  test "walking the cursors reaches the first line and then runs out" do
    write_history(PAGE * 2 + 3)
    sign_in_as(@reader)
    pages = []
    url = conversation_messages_path(@conversation)

    while url
      get url
      assert_response :success
      pages << response.body.scan(/line (\d+)/).flatten.map(&:to_i)
      url = response.headers["X-History-Next"]
    end

    # Pages walk newest to oldest, each ascending; read back to front they
    # reproduce the whole thread from its first line, with no line twice.
    assert_equal (0...(PAGE * 2 + 3)).to_a, pages.reverse.flatten
    assert_not response.headers.key?("X-History-Next")
  end

  test "history renders neither expired nor unsent messages" do
    write_history(4)
    # Both picked before either changes: once line 0 is unsent, "the second
    # visible message" is line 2, and line 1 was never expired at all.
    visible = @conversation.messages.visible
    in_order = visible.order(:created_at)
    unsent, expired = in_order.first(2)
    unsent.update!(deleted_at: Time.current)
    expired.update_columns(expires_at: 1.hour.ago)
    sign_in_as(@reader)

    get conversation_messages_path(@conversation)

    assert_response :success
    refute_includes response.body, "line 0"
    refute_includes response.body, "line 1"
    assert_includes response.body, "line 3"
  end

  test "a stranger gets no history from a thread they are not in" do
    write_history(3)
    sign_in_as(@stranger)

    get conversation_messages_path(@conversation)

    assert_response :not_found
  end

  # A broadcast sent while the socket was down is not replayed; the log asks for
  # what came after its newest line when the stream, the network or the tab
  # comes back.
  test "after= returns the lines newer than the cursor, oldest first, as this reader sees them" do
    write_history(4)
    lines = @conversation.messages.order(:id).to_a
    lines.last.unsend!
    sign_in_as(@reader)

    get conversation_messages_path(@conversation, after: lines[1].id)

    assert_response :success
    assert_select "li[id]", count: 1, text: /line 2/
    refute_includes response.body, "line 1"
    assert_nil response.headers["X-Catch-Up-More"]
    assert_select "article[data-from=peer]", count: 1
  end

  test "after= pages a long absence and answers nothing new with no content" do
    write_history(PAGE + 2)
    first = @conversation.messages.minimum(:id)
    sign_in_as(@reader)

    get conversation_messages_path(@conversation, after: first)
    assert_equal "1", response.headers["X-Catch-Up-More"]
    assert_select "li[id^=message_]", count: PAGE

    get conversation_messages_path(@conversation, after: @conversation.messages.maximum(:id))
    assert_response :no_content
  end

  test "a stranger catches up on nothing" do
    write_history(2)
    sign_in_as(@stranger)

    get conversation_messages_path(@conversation, after: 0)

    assert_response :not_found
  end
end
