# frozen_string_literal: true

require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @kari = user("conv_kari")
    @ola = user("conv_ola")
    @third = user("conv_third")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123", username: name, guest: false
    )
  end

  # for_user(a).for_user(b) reads as an intersection and is not one: both scopes
  # join the same association, Rails collapses them, and the predicates AND on a
  # single row. Until this test, every pair got a new thread each time they
  # opened a DM from a different button.
  test "the same pair keeps one thread" do
    first = Conversation.find_or_create_direct(@kari, @ola)
    second = Conversation.find_or_create_direct(@kari, @ola)
    reversed = Conversation.find_or_create_direct(@ola, @kari)

    assert_equal first.id, second.id
    assert_equal first.id, reversed.id
    assert_equal 1, Conversation.where(conversation_type: "direct").count
  end

  test "a different pair is a different thread" do
    theirs = Conversation.find_or_create_direct(@kari, @ola)
    mine = Conversation.find_or_create_direct(@kari, @third)

    assert_not_equal theirs.id, mine.id
    assert_nil Conversation.direct_between(@ola, @third)
  end

  test "the same pair gets a separate private thread in each city" do
    bergen_thread = Conversation.find_or_create_direct(@kari, @ola)
    oslo = City.find_by!(domain: "oshlo.no")
    ActsAsTenant.current_tenant = oslo

    oslo_thread = Conversation.find_or_create_direct(@kari, @ola)

    refute_equal bergen_thread.id, oslo_thread.id
    assert_equal @city.id, bergen_thread.reload.city_id
    assert_equal oslo.id, oslo_thread.reload.city_id
    assert_equal [ oslo_thread.id ], Conversation.for_user(@kari).where(slug: nil).pluck(:id)
    assert_equal oslo_thread.id, Conversation.direct_between(@kari, @ola).id

    ActsAsTenant.current_tenant = @city
    assert_equal [ bergen_thread.id ], Conversation.for_user(@kari).where(slug: nil).pluck(:id)
    assert_equal bergen_thread.id, Conversation.direct_between(@kari, @ola).id
  end

  test "a legacy unassigned direct thread is pinned to Bergen when reopened" do
    legacy = Conversation.create!(conversation_type: "direct")
    legacy.participants << @kari << @ola

    assert_equal legacy.id, Conversation.direct_between(@kari, @ola).id
    assert_equal @city.id, legacy.reload.city_id

    oslo = City.find_by!(domain: "oshlo.no")
    ActsAsTenant.current_tenant = oslo
    refute_includes Conversation.for_user(@kari).pluck(:id), legacy.id
    assert_nil Conversation.direct_between(@kari, @ola)
  end

  # A group room is not a DM, however many people are in it.
  test "a group is never returned as a direct thread" do
    group = Conversation.create_group!(creator: @kari, name: "Turgruppa", users: [ @ola ])

    assert_not_equal group.id, Conversation.find_or_create_direct(@kari, @ola).id
  end
end
