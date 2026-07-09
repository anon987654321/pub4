# frozen_string_literal: true

require "test_helper"

class CityTenantTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @bergen = City.find_by!(domain: "brgen.no")
    @los_angeles = City.find_by!(domain: "lsangeles.com")
    @admin = User.strict_loading(false).create!(
      email_address: "tenant_admin@brgen.no",
      password: "password123",
      city: @bergen
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "posts are isolated per city tenant" do
    bergen_post = nil
    la_post = nil

    ActsAsTenant.with_tenant(@bergen) do
      community = Community.create!(slug: "test-bergen", name: "Test Bergen", user: @admin, city: @bergen)
      bergen_post = Post.create!(user: @admin, community: community, title: "Bergen only", content: "Hei")
    end

    ActsAsTenant.with_tenant(@los_angeles) do
      la_admin = User.strict_loading(false).create!(
        email_address: "tenant_admin@lsangeles.com",
        password: "password123",
        city: @los_angeles
      )
      community = Community.create!(slug: "test-la", name: "Test LA", user: la_admin, city: @los_angeles)
      la_post = Post.create!(user: la_admin, community: community, title: "LA only", content: "Hello")
    end

    ActsAsTenant.with_tenant(@bergen) do
      titles = Post.pluck(:title)
      assert_includes titles, bergen_post.title
      assert_not_includes titles, la_post.title
    end
  end
end