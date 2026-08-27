# frozen_string_literal: true

require "test_helper"

# The messenger's read paths used to scale with content: opening a room did two
# queries per message, and listing the channels did two per room. Both are now
# fixed-cost, and a budget is the only kind of test that keeps them that way —
# an assertion on the result would pass just as happily at two hundred queries.
class MessengerQueryBudgetTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @me = create_user("me")
    @other = create_user("other")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def create_user(handle)
    User.create!(email_address: "#{handle}-#{SecureRandom.hex(4)}@brgen.no",
                 password: "password123", password_confirmation: "password123",
                 username: "#{handle}_#{SecureRandom.hex(3)}", city: @city)
  end

  def count_queries
    n = 0
    counter = ->(_name, _start, _finish, _id, payload) do
      n += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  def conversation_with(count)
    convo = Conversation.find_or_create_direct(@me, @other)
    count.times { |i| convo.messages.create!(sender: @other, content: "m#{i}", message_type: "text") }
    convo
  end

  # The number is not the point; its independence from the message count is.
  test "marking a room read costs the same at 5 messages as at 40" do
    small = conversation_with(5)
    small.mark_read_for!(@me)
    MessageReceipt.where(user: @me).delete_all
    few = count_queries { small.mark_read_for!(@me) }

    big = conversation_with(40)
    big.mark_read_for!(@me)
    MessageReceipt.where(user: @me).delete_all
    many = count_queries { big.mark_read_for!(@me) }

    assert_equal few, many,
                 "mark_read_for! grew from #{few} to #{many} queries between 5 and 40 messages"
    assert_operator many, :<=, 8, "#{many} queries to mark one room read"
  end

  test "a second read of the same room writes nothing new" do
    convo = conversation_with(5)
    convo.mark_read_for!(@me)
    before = MessageReceipt.where(user: @me).pluck(:message_id, :read_at).to_h

    convo.mark_read_for!(@me)
    after = MessageReceipt.where(user: @me).pluck(:message_id, :read_at).to_h

    assert_equal before, after, "re-reading a room moved the first-read times"
  end

  test "channel counts are one query each regardless of how many rooms" do
    rooms = Conversation.channels.to_a
    n = count_queries do
      Conversation.message_counts_for(rooms)
      Conversation.active_counts_for(rooms)
    end

    assert_operator n, :<=, 2, "#{n} queries for two grouped counts"
  end
end
