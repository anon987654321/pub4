# frozen_string_literal: true

require "test_helper"

class ConversationPinsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @user = create_user("pin_user")
    @friend = create_user("pin_friend")
    @stranger = create_user("pin_stranger")
    ActsAsTenant.current_tenant = @city
    @old = Conversation.find_or_create_direct(@user, @friend)
    @new = Conversation.find_or_create_direct(@user, create_user("pin_other"))
    Message.create!(conversation: @old, sender: @friend, content: "eldre", message_type: "text")
    travel 1.hour
    Message.create!(conversation: @new, sender: @user, content: "nyere", message_type: "text")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def participant(conversation, user)
    ConversationParticipant.find_by!(conversation: conversation, user: user)
  end

  # The order the reader actually sees, read off the rendered list: pinning is a
  # claim about the page, not about a relation.
  def rendered_order
    get conversations_path
    response.body.scan(%r{/conversations/(\d+)}).flatten.map(&:to_i).uniq
  end

  test "pinning lifts an older thread above a newer one" do
    sign_in_as(@user)
    assert_equal [ @new.id, @old.id ], rendered_order

    post conversation_pin_path(@old)
    assert_predicate participant(@old, @user).reload, :pinned?

    assert_equal [ @old.id, @new.id ], rendered_order
  end

  test "unpinning restores recency order" do
    sign_in_as(@user)
    post conversation_pin_path(@old)

    delete conversation_pin_path(@old)
    assert_nil participant(@old, @user).reload.pinned_at
    assert_equal [ @new.id, @old.id ], rendered_order
  end

  # A pin is the viewer's own ordering, so the other side of the thread keeps
  # theirs. Pinning the shared record would reorder someone else's inbox.
  test "a pin is the pinner's alone" do
    sign_in_as(@user)
    post conversation_pin_path(@old)

    assert_nil participant(@old, @friend).pinned_at
  end

  # The participant row is the membership check: someone who is not in the
  # thread has no row to pin.
  test "a stranger cannot pin a thread they are not in" do
    sign_in_as(@stranger)

    post conversation_pin_path(@old)
    assert_response :not_found
  end

  test "a passing visitor cannot pin either" do
    host! "brgen.no"
    # brgen mints a guest User per visitor, and a guest is in no conversation,
    # so the same not-a-participant path answers.
    post conversation_pin_path(@old)
    assert_response :not_found
  end
end
