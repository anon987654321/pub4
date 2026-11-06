# frozen_string_literal: true

require "test_helper"

# unread_count_for is two queries per conversation. The layout summed it across
# every DM on every authenticated render, and the messenger index ran it per row,
# so the badge alone cost 2N queries on each pageview of each page.
#
# unread_total_for / unread_counts_for express the same predicate in one query.
# The point of this file is that "the same predicate" is literally true: every
# assertion below checks the set-based answer against the per-record one rather
# than against a hand-written expectation, so the two cannot drift apart.
class UnreadCountsTest < ActiveSupport::TestCase
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

  def dm_with(other, messages: 0, sender: nil)
    convo = Conversation.find_or_create_direct(@me, other)
    messages.times { |i| convo.messages.create!(content: "m#{i}", sender: sender || other, message_type: "text") }
    convo
  end

  # The invariant: whatever the old per-record method says, the new set-based
  # methods must say the same, for every conversation and in total.
  def assert_agrees_with_per_record(scope_ids)
    per_record = scope_ids.index_with { |id| Conversation.find(id).unread_count_for(@me) }
    counts = Conversation.unread_counts_for(@me)
    scope_ids.each do |id|
      assert_equal per_record[id], counts.fetch(id, 0),
                   "unread_counts_for disagreed with unread_count_for on conversation #{id}"
    end
    per_record
  end

  test "counts_for agrees with unread_count_for, unread and read alike" do
    unread = dm_with(@other, messages: 3)
    read = dm_with(create_user("read"), messages: 2)
    read.mark_read_for!(@me)
    empty = dm_with(create_user("empty"))

    per_record = assert_agrees_with_per_record([ unread.id, read.id, empty.id ])
    assert_equal 3, per_record[unread.id], "a never-opened thread has everything unread"
    assert_equal 0, per_record[read.id], "mark_read_for! clears it"
    assert_equal 0, per_record[empty.id], "no messages, nothing unread"
  end

  test "only messages after last_read_at count" do
    convo = dm_with(@other, messages: 2)
    convo.mark_read_for!(@me)
    travel 1.minute do
      convo.messages.create!(content: "after", sender: @other, message_type: "text")
      assert_equal 1, Conversation.unread_counts_for(@me).fetch(convo.id, 0)
      assert_equal convo.unread_count_for(@me), Conversation.unread_counts_for(@me).fetch(convo.id, 0)
    end
  end

  # The join fans each message out once per participant; if the user_id filter
  # failed to collapse it, a 2-person thread would double-count.
  test "a message is counted once, not once per participant" do
    convo = dm_with(@other, messages: 4)
    assert_equal 2, convo.participants.count, "guard: this is a 2-person thread"
    assert_equal 4, Conversation.unread_counts_for(@me).fetch(convo.id, 0)
  end

  test "total matches the sum the layout used to compute in Ruby" do
    a = dm_with(@other, messages: 3)
    b = dm_with(create_user("b"), messages: 2)
    ids = [ a.id, b.id ]

    old_way = Conversation.for_user(@me).where(slug: nil).sum { |c| c.unread_count_for(@me) }
    assert_equal old_way, Conversation.unread_total_for(@me)
    assert_equal 5, Conversation.unread_total_for(@me)
    assert_agrees_with_per_record(ids)
  end

  # The badge is DMs only. A channel is a group Conversation with a slug, and it
  # is ambient — unread traffic there must not light the icon.
  test "channels are excluded from the badge total but not from counts_for" do
    dm = dm_with(@other, messages: 2)
    channel = Conversation.find_or_create_channel("brgen", city: @city)
    channel.conversation_participants.find_or_create_by!(user: @me)
    channel.messages.create!(content: "ambient", sender: @other, message_type: "text")

    assert_equal 2, Conversation.unread_total_for(@me), "channel traffic must not reach the badge"
    assert_operator Conversation.unread_counts_for(@me).fetch(channel.id, 0), :>, 0,
                    "counts_for is unfiltered — the caller decides what to show"
    assert_equal dm.unread_count_for(@me), Conversation.unread_counts_for(@me).fetch(dm.id, 0)
  end

  # The regression this whole change exists to prevent.
  test "the total is one query regardless of how many threads there are" do
    5.times { |i| dm_with(create_user("q#{i}"), messages: 2) }

    queries = 0
    counter = ->(_n, _s, _f, _i, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      Conversation.unread_total_for(@me)
    end
    assert_equal 1, queries, "unread_total_for must not scale with thread count"
  end
end
