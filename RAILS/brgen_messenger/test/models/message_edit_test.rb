# frozen_string_literal: true

require "test_helper"

# A typo stood forever, and a message sent to the wrong room could not be taken
# back — which on a hyperlocal chat where people post real addresses is a safety
# gap rather than a convenience one.
class MessageEditTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @sender = User.strict_loading(false).create!(
      email_address: "me_sender@brgen.no", password: "password123", city: @city
    )
    @other = User.strict_loading(false).create!(
      email_address: "me_other@brgen.no", password: "password123", city: @city
    )
    @conversation = Conversation.find_or_create_direct(@sender, @other)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sent_message(sender: @sender, content: "Hei", **attrs)
    @conversation.messages.create!({ sender: sender, content: content, message_type: "text" }.merge(attrs))
  end

  test "the sender can edit inside the window and nobody else ever can" do
    m = sent_message

    assert m.editable_by?(@sender)
    refute m.editable_by?(@other)

    m.edit!("Hei igjen")
    assert_equal "Hei igjen", m.reload.content
    assert m.edited?
  end

  # A message that can be rewritten hours later is one a reader cannot trust,
  # and the receipt saying they read it is already gone.
  test "editing closes after the window" do
    m = sent_message
    m.update_columns(created_at: (Message::EDIT_WINDOW + 1.minute).ago)

    refute m.reload.editable_by?(@sender)
  end

  # Unsending has no window: a message in the wrong room is a safety problem.
  test "unsending has no window and empties the body but keeps the row" do
    m = sent_message(content: "Adressen min er Marken 4")
    m.update_columns(created_at: 3.days.ago)

    assert m.reload.deletable_by?(@sender)
    assert_no_difference -> { Message.count } do
      m.unsend!
    end

    assert m.reload.deleted?
    assert_equal "", m.content
  end

  # The row survives so a threaded reply is not orphaned.
  test "a reply to an unsent message still has its parent" do
    parent = sent_message(content: "Spørsmål")
    reply = sent_message(sender: @other, content: "Svar", parent: parent)

    parent.unsend!

    assert_equal parent.id, reply.reload.parent_id
    assert reply.reply?
    assert_includes Message.where(parent_id: parent.id).map(&:id), reply.id
  end

  # Without exempting deleted messages from the presence validation the record
  # is permanently invalid, and every later save on it — a receipt, a reaction —
  # would fail.
  test "an unsent message can still be saved afterwards" do
    m = sent_message
    m.unsend!

    assert m.reload.valid?
    assert m.update(expires_at: 1.hour.from_now)
  end

  test "a second unsend is refused rather than being a no-op that looks like one" do
    m = sent_message
    m.unsend!

    refute m.reload.deletable_by?(@sender)
  end

  test "visible drops unsent messages from a render" do
    kept = sent_message(content: "Blir")
    gone = sent_message(content: "Forsvinner")
    gone.unsend!

    ids = @conversation.messages.visible.map(&:id)
    assert_includes ids, kept.id
    refute_includes ids, gone.id
  end
end
