# frozen_string_literal: true

require "test_helper"

# A changed disappearing timer is said in the thread, by whoever changed it,
# so the other side is not left with messages that vanish on a timer nobody
# told them about.
class DisappearingChangeLineTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @user = create_user("timer_user")
    @friend = create_user("timer_friend")
    @conversation = Conversation.find_or_create_direct(@user, @friend)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(name)
    User.strict_loading(false).create!(email_address: "#{name}_#{SecureRandom.hex(3)}@brgen.no",
                                       password: "password123", username: "#{name}_#{SecureRandom.hex(3)}",
                                       guest: false)
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "a changed timer is a line from whoever changed it, and an unchanged one is not" do
    sign_in_as(@user)
    line = I18n.t("messages.disappearing_changed", setting: I18n.t("messages.disappearing_options.1h"))

    assert_difference -> { @conversation.messages.where(sender: @user).count }, 1 do
      patch conversation_path(@conversation), params: { disappearing: "1h" }
    end
    latest = @conversation.messages.order(:id).last
    assert_equal line, latest.content
    assert_no_difference -> { @conversation.messages.count } do
      patch conversation_path(@conversation), params: { disappearing: "1h" }
    end

    sign_in_as(@friend)
    get conversation_path(@conversation)
    assert_includes response.body, CGI.escapeHTML(line)
  end
end
