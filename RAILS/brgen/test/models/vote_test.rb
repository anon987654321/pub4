# frozen_string_literal: true

require "test_helper"

class VoteTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @author = User.strict_loading(false).create!(email_address: "author@brgen.no", password: "password123", city: @city)
    @voter = User.strict_loading(false).create!(email_address: "voter@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "updates author karma when post is upvoted" do
    ActsAsTenant.with_tenant(@city) do
      community = Community.create!(slug: "vote-test", name: "Vote Test", user: @author, city: @city)
      post = Post.create!(user: @author, community: community, title: "Karma check", content: "Hello")

      Vote.create!(user: @voter, votable: post, value: 1)

      assert_equal 1, @author.reload.karma
    end
  end

  test "requires unique vote per user and votable" do
    ActsAsTenant.with_tenant(@city) do
      community = Community.create!(slug: "vote-dup", name: "Vote Dup", user: @author, city: @city)
      post = Post.create!(user: @author, community: community, title: "Once", content: "Hi")
      Vote.create!(user: @voter, votable: post, value: 1)
      duplicate = Vote.new(user: @voter, votable: post, value: -1)

      assert_not duplicate.valid?
      assert_includes duplicate.errors[:user_id], I18n.t("errors.messages.taken")
    end
  end
end