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
end
