# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# A reaction on a chat line is broadcast once, from the reactor's request, to
# everyone in the room. Rendered as the reactor, every reader saw the reactor's
# chip pressed as their own.
class MessageReactionsTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @reactor = create_user("react_reactor")
    @friend = create_user("react_friend")
    ActsAsTenant.current_tenant = @city
    @conversation = Conversation.find_or_create_direct(@reactor, @friend)
    @message = Message.create!(conversation: @conversation, sender: @friend,
                               content: "Pizza i kveld?", message_type: "text")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
    Current.reset
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

  test "the broadcast chip presses nobody's reaction and names who reacted" do
    Current.user = @reactor
    streams = capture_turbo_stream_broadcasts(@conversation) do
      Reaction.create!(user: @reactor, reactable: @message, kind: "love")
    end
    html = streams.last.to_html

    assert_equal "replace", streams.last["action"]
    assert_includes html, %(data-reactor-ids="#{@reactor.id}")
    refute_includes html, "is_mine", "the reactor's chip is not every reader's chip"
    assert_includes html, 'aria-pressed="false"'
  end

  test "an un-reaction broadcasts the chip row without the gone reaction" do
    reaction = Reaction.create!(user: @reactor, reactable: @message, kind: "love")
    streams = capture_turbo_stream_broadcasts(@conversation) { reaction.destroy! }

    refute_includes streams.last.to_html, "data-reactor-ids"
  end

  test "the reactor's own response keeps the message chips, pressed for them" do
    sign_in_as(@reactor)
    post reactions_path, params: { target_gid: @message.to_signed_global_id.to_s, kind: "laugh" },
                         as: :turbo_stream

    assert_response :success
    assert_includes response.body, "msg_reaction_chip is_mine", "the chat chip row, not the post bar"
    assert_includes response.body, %(target="reactions_#{ActionView::RecordIdentifier.dom_id(@message)}")
  end

  # Two queries per line (a grouped COUNT and an EXISTS per kind) was the cost
  # of the chips. Preloaded, the row reads what is in memory.
  test "a preloaded chip row asks the database nothing" do
    Reaction.create!(user: @reactor, reactable: @message, kind: "love")
    Reaction.create!(user: @friend, reactable: @message, kind: "love")
    message = Message.strict_loading(false).includes(:reactions).find(@message.id)
    Current.user = @friend

    queries = []
    counter = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached] }
    html = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      ApplicationController.render(partial: "messages/reactions", locals: { message: })
    end

    assert_empty queries
    assert_includes html, "is_mine"
    assert_includes html, %(<span class="msg_reaction_count">2</span>)
  end
end
