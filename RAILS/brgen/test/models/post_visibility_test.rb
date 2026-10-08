# frozen_string_literal: true

require "test_helper"

class PostVisibilityTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(email_address: "vis_own@brgen.no", password: "password123", city: @city)
    @member = User.strict_loading(false).create!(email_address: "vis_mem@brgen.no", password: "password123", city: @city)
    @stranger = User.strict_loading(false).create!(email_address: "vis_str@brgen.no", password: "password123", city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "a private community post is hidden from strangers and the public feed" do
    ActsAsTenant.with_tenant(@city) do
      community = Community.create!(user: @owner, name: "Hemmelig #{SecureRandom.hex(3)}", privacy: "private")
      community.community_memberships.create!(user: @owner, role: "owner")
      @member.join_community!(community)
      post = Post.create!(user: @owner, community: community, title: "Inne", content: "kun medlemmer")

      assert post.readable_by?(@owner)
      assert post.readable_by?(@member)
      refute post.readable_by?(@stranger)
      refute post.readable_by?(nil)

      ids = Post.visible_to(@stranger).pluck(:id)
      refute_includes ids, post.id
      assert_includes Post.visible_to(@member).pluck(:id), post.id
    end
  end
end
