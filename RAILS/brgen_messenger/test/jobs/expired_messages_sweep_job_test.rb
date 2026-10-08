# frozen_string_literal: true

require "test_helper"

# The sweep runs every fifteen minutes and MessageExpirationJob can reach the
# same message, so expiry has to happen once: a second pass must not restamp
# deleted_at on a message already gone.
class ExpiredMessagesSweepJobTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    a = User.strict_loading(false).create!(email_address: "sweep_a@brgen.no", password: "password123", username: "sweep_a", guest: false)
    b = User.strict_loading(false).create!(email_address: "sweep_b@brgen.no", password: "password123", username: "sweep_b", guest: false)
    conversation = Conversation.find_or_create_direct(a, b)
    @message = Message.create!(conversation: conversation, sender: a, content: "Forsvinner", message_type: "text")
    @message.update_columns(expires_at: 1.minute.ago)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "an expired message is emptied once, and a second sweep leaves it alone" do
    ExpiredMessagesSweepJob.perform_now
    first = @message.reload.deleted_at
    assert_equal "", @message.content
    assert first

    travel 20.minutes do
      ExpiredMessagesSweepJob.perform_now
      Message.find(@message.id).expire!
    end

    assert_equal first.to_i, @message.reload.deleted_at.to_i
  end
end
