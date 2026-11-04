# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# What the inbox and a thread draw, line by line: the limits the composer
# states, what a screen reader hears, what a reply points at, and which box is
# open while a line is being edited.
class MessengerViewTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = create_user("view_user")
    @friend = create_user("view_friend")
    @conversation = Conversation.find_or_create_direct(@user, @friend)
    @friend.update_columns(display_name: "Venn Visning")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "#{name}_#{SecureRandom.hex(3)}", guest: false
    )
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def line(content, sender: @friend, **attrs)
    Message.create!(conversation: @conversation, sender:, content:, message_type: "text", **attrs)
  end

  test "the composer allows as many characters as a message may hold" do
    sign_in_as(@user)
    get conversation_path(@conversation)

    assert_select "form#new_message textarea[maxlength=?]", Message::MAX_LENGTH.to_s
  end

  test "the inbox has one h1 and its unread count is spoken" do
    line("uleste ord")
    sign_in_as(@user)
    get conversations_path

    assert_select "h1", count: 1
    assert_select ".messenger-inbox-meta .visually-hidden", text: I18n.t("messages.unread_badge", count: 1, locale: :nb)
  end

  test "a channel's presence count is translated" do
    html = ChannelPresence.stub(:count_for, 3) do
      ApplicationController.render(partial: "conversations/presence", locals: { conversation: @conversation })
    end

    assert_includes html, I18n.t("messages.here_now", count: 3, locale: :nb)
    refute_includes html, "here now"
  end

  test "a DM shows the other person's identicon in its header and its rail row" do
    line("hei")
    sign_in_as(@user)

    get conversation_path(@conversation)

    assert_select "header.messenger-conversation-header img.messenger-header-avatar[src=?][alt='']", @friend.avatar_url
    rail = "##{ActionView::RecordIdentifier.dom_id(@conversation, :rail)} img.messenger-room-avatar[src=?]"
    assert_select rail, @friend.avatar_url
  end

  test "a group's member list shows each member's identicon" do
    group = Conversation.create!(conversation_type: "group", name: "Gjengen", city: @city)
    [ @user, @friend ].each { |member| group.join!(member) }
    sign_in_as(@user)

    get conversation_path(group)

    [ @user, @friend ].each do |member|
      assert_select ".messenger-member-list img.messenger-member-avatar[src=?]", member.avatar_url
    end
    assert_select "img.messenger-header-avatar", 0
  end

  test "a DM's header name opens the other person's profile" do
    sign_in_as(@user)
    get conversation_path(@conversation)

    assert_select ".messenger-header-identity h1 a[href=?]", user_path(@friend), text: "Venn Visning"
  end

  test "editing a line replaces the composer and says until when it can be edited" do
    mine = line("rett meg", sender: @user)
    sign_in_as(@user)
    get conversation_path(@conversation, edit: mine.id)

    assert_select "form.messenger-edit-form textarea[aria-describedby='edit_window_note']"
    assert_select "#edit_window_note.form-help"
    assert_select "form#new_message", count: 0
  end

  test "a reply links to its parent, and an unsent parent reads as gone" do
    parent = line("første")
    reply = line("svar", sender: @user, parent_id: parent.id)
    gone = line("angret")
    orphan = line("svar på angret", sender: @user, parent_id: gone.id)
    gone.update_columns(deleted_at: Time.current, content: "")
    sign_in_as(@user)
    get conversation_path(@conversation)

    assert_select "##{ActionView::RecordIdentifier.dom_id(reply)} .msg-reply-context a[href=?]",
                  "##{ActionView::RecordIdentifier.dom_id(parent)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(orphan)} .msg-reply-context",
                  text: I18n.t("messages.parent_gone", locale: :nb)
  end

  test "the line a reply links to is marked on arrival" do
    css = Rails.root.join("app/assets/stylesheets/_brgen_messenger.scss").read

    assert_match(/\.conversation-log > li:target > article \{\s*animation: messenger-reply-target/, css)
  end

  test "the actions disclosure is styled on brgen.no as well as the messenger host" do
    css = Rails.root.join("app/assets/stylesheets/_brgen_messenger.scss").read

    assert_match(/^\.messenger-pane \.msg-actions summary \{/, css)
  end

  test "a photo says whose it is and sits above the line's actions" do
    photo = Message.new(conversation: @conversation, sender: @friend, content: "", message_type: "text")
    photo.attachment.attach(io: StringIO.new(file_fixture_png), filename: "IMG_4031.png", content_type: "image/png")
    photo.save!
    sign_in_as(@user)
    get conversation_path(@conversation)

    article = css_select("##{ActionView::RecordIdentifier.dom_id(photo)} article").first
    assert article
    image = article.at_css("img")
    assert_equal I18n.t("messages.photo_from", name: "Venn Visning", locale: :nb), image["alt"]
    html = article.to_html
    assert_operator html.index("<img"), :<, html.index("<details")
  end

  test "a voice note names its sender and shows its length" do
    voice = Message.new(conversation: @conversation, sender: @friend, content: "",
                        message_type: "audio", duration_seconds: 75)
    voice.attachment.attach(io: StringIO.new("ID3"), filename: "voice.webm", content_type: "audio/webm")
    voice.save!
    sign_in_as(@user)
    get conversation_path(@conversation)

    assert_select "audio[aria-label=?]", I18n.t("messages.voice_note_from", name: "Venn Visning", locale: :nb)
    assert_select "time.msg-voice-duration[datetime='PT75S']", text: "1:15"
  end

  # Each line carried a select of every other thread, fifty copies a page. A
  # line links to one picker now, which loads the threads when it is opened.
  test "each line links to the forward picker, which lists the other threads once" do
    third = create_user("view_third")
    Conversation.find_or_create_direct(@user, third)
    first = line("en")
    second = line("to")
    sign_in_as(@user)
    get conversation_path(@conversation)

    assert_select "select[name=target_conversation_id]", 0
    [ first, second ].each do |message|
      assert_select "a[href=?]", forward_to_conversation_message_path(@conversation, message), 1
    end

    get forward_to_conversation_message_path(@conversation, first)
    assert_response :success
    assert_select "form[action=?] select[name=target_conversation_id]",
                  forward_conversation_message_path(@conversation, first) do
      assert_select "option", text: third.display_name
    end
    assert_select "label[for=target_conversation_id]", I18n.t("messages.forward_to")
  end

  private

  def file_fixture_png
    Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
  end
end
