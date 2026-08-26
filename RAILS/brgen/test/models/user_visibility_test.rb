# frozen_string_literal: true

require "test_helper"

# Users are global identities, not tenant rows. vote_test and city_tenant_test
# both create their users with an explicit `city:`, so neither noticed that a
# user without one became invisible the moment a tenant was active -- which is
# every request. That nil'd post.user, message.sender and User.nearby.
class UserVisibilityTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    # No city:, and created outside any tenant -- exactly how resume_session
    # makes a guest and how the seeders make demo accounts.
    @author = User.strict_loading(false).create!(email_address: "cityless_author@brgen.no", password: "password123", username: "cityless_author")
    @voter = User.strict_loading(false).create!(email_address: "cityless_voter@brgen.no", password: "password123")
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a user without a city is still visible while a tenant is active" do
    ActsAsTenant.with_tenant(@city) do
      assert_equal @author, User.find_by(id: @author.id)
      assert_includes User.pluck(:id), @voter.id
    end
  end

  test "post author resolves for an author with no city" do
    ActsAsTenant.with_tenant(@city) do
      community = Community.create!(slug: "visibility", name: "Visibility", user: @author, city: @city)
      post = Post.create!(user: @author, community: community, title: "Named byline", content: "Hei")

      assert_equal @author, Post.strict_loading(false).find(post.id).user
      assert_not_equal "anon", Post.strict_loading(false).find(post.id).author_name
    end
  end

  test "voting on a post by a city-less author updates karma instead of raising" do
    ActsAsTenant.with_tenant(@city) do
      community = Community.create!(slug: "visibility-vote", name: "Visibility Vote", user: @author, city: @city)
      post = Post.create!(user: @author, community: community, title: "Karma", content: "Hei")

      Vote.create!(user: @voter, votable: post, value: 1)

      assert_equal 1, @author.reload.karma
    end
  end

  test "message sender resolves in a channel conversation" do
    ActsAsTenant.with_tenant(@city) do
      channel = Conversation.create!(conversation_type: "group", slug: "brgen", name: "#brgen", city: @city)
      message = channel.messages.create!(sender: @author, content: "hei", message_type: "text")

      assert_equal @author, Message.strict_loading(false).find(message.id).sender
      assert_match(/Stranger #/, Message.strict_loading(false).find(message.id).sender.channel_handle)
    end
  end

  test "nearby finds a user who has no city" do
    @author.update_columns(latitude: 60.39, longitude: 5.32, location_updated_at: Time.current)

    ActsAsTenant.with_tenant(@city) do
      assert_includes User.nearby(60.39, 5.32, 10).map(&:id), @author.id
    end
  end
end
