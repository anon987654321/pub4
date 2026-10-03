# frozen_string_literal: true

require "test_helper"

class Dating::MatchTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @initiator = User.strict_loading(false).create!(email_address: "match_a@brgen.no", password: "password123", city: @city)
    @receiver = User.strict_loading(false).create!(email_address: "match_b@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "requires unique initiator and receiver pair" do
    ActsAsTenant.with_tenant(@city) do
      Dating::Match.create!(initiator: @initiator, receiver: @receiver, status: "matched")
      duplicate = Dating::Match.new(initiator: @initiator, receiver: @receiver, status: "matched")

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:initiator_id], I18n.t("errors.messages.taken")
    end
  end

  test "other_user returns the opposite participant" do
    ActsAsTenant.with_tenant(@city) do
      match = Dating::Match.create!(initiator: @initiator, receiver: @receiver, status: "matched")

      assert_equal @receiver, match.other_user(@initiator)
      assert_equal @initiator, match.other_user(@receiver)
    end
  end

  # The test above builds the match with both users already in memory. A match
  # reached from a controller or a view is found by id with nothing preloaded,
  # and ApplicationRecord is strict_loading by default — the same shape that
  # broke Marketplace::Order#mark_paid! and Takeaway::Order#transition_to!.
  test "other_user on a freshly-found match does not violate strict loading" do
    ActsAsTenant.with_tenant(@city) do
      id = Dating::Match.create!(initiator: @initiator, receiver: @receiver, status: "matched").id
      found = Dating::Match.find(id)

      assert_equal @receiver.id, found.other_user(@initiator).id
      assert_equal @initiator.id, found.other_user(@receiver).id
    end
  end

  test "status is restricted to the three known states" do
    match = Dating::Match.new(initiator: @initiator, receiver: @receiver, status: "friends")

    assert_not match.valid?
    assert_includes match.errors[:status], I18n.t("errors.messages.inclusion")
  end

  test "active scope returns matched and excludes pending" do
    ActsAsTenant.with_tenant(@city) do
      matched = Dating::Match.create!(initiator: @initiator, receiver: @receiver, status: "matched")
      pending = Dating::Match.create!(initiator: @receiver, receiver: @initiator, status: "pending")

      assert_includes Dating::Match.active, matched
      assert_not_includes Dating::Match.active, pending
    end
  end

  # announce_match runs after_create_commit and reaches both users through
  # other_user, so the lazy read sits on the write path too.
  test "a matched pair notifies both users on create" do
    ActsAsTenant.with_tenant(@city) do
      assert_difference "Notification.count", 2 do
        Dating::Match.create!(initiator: @initiator, receiver: @receiver, status: "matched")
      end
    end
  end

  test "unmatch ends the match and clears the likes so they can like again" do
    ActsAsTenant.with_tenant(@city) do
      Dating::Like.create!(liker: @initiator, likee: @receiver)
      Dating::Like.create!(liker: @receiver, likee: @initiator)
      match = Dating::Match.between(@initiator, @receiver)
      assert_equal "matched", match.status

      assert match.unmatch!
      assert_equal "unmatched", match.reload.status
      assert_not_includes Dating::Match.active, match
      assert_equal 0, Dating::Like.where(liker: [ @initiator, @receiver ]).count

      Dating::Like.create!(liker: @initiator, likee: @receiver)
      Dating::Like.create!(liker: @receiver, likee: @initiator)
      assert_equal "matched", match.reload.status
    end
  end

  test "unmatch on a freshly-found match does not violate strict loading" do
    ActsAsTenant.with_tenant(@city) do
      id = Dating::Match.create!(initiator: @initiator, receiver: @receiver, status: "matched").id
      found = Dating::Match.find(id)

      assert found.unmatch!
      assert_equal "unmatched", found.reload.status
    end
  end

  test "a pending match announces nothing" do
    ActsAsTenant.with_tenant(@city) do
      assert_no_difference "Notification.count" do
        Dating::Match.create!(initiator: @initiator, receiver: @receiver, status: "pending")
      end
    end
  end
end
