# frozen_string_literal: true

require "test_helper"

# Shared::Sluggable wired into Post (representative title-based, city-scoped model).
# The concern is identical across the five content models; this pins the behaviour
# the URLs depend on: a slug is derived, to_param returns it, and same-title records
# in one city disambiguate instead of colliding.
class SluggableTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @user = User.create!(email_address: "slug-#{SecureRandom.hex(4)}@example.com", password: "password12345")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "derives a url-safe slug from the title and returns it as to_param" do
    post = Post.create!(title: "Sol på Fløyen i dag!", user: @user)
    assert_equal "sol-pa-floyen-i-dag", post.slug
    assert_equal post.slug, post.to_param
  end

  test "disambiguates same-title posts within a city with a numeric suffix" do
    a = Post.create!(title: "Samme tittel", user: @user)
    b = Post.create!(title: "Samme tittel", user: @user)
    assert_equal "samme-tittel", a.slug
    assert_equal "samme-tittel-2", b.slug
  end

  test "underscores in the title become hyphens so the slug stays url-safe" do
    post = Post.create!(title: "Hei @mn_named på Bryggen", user: @user)
    assert_equal "hei-mn-named-pa-bryggen", post.slug
  end

  test "blank-derived titles fall back to a stable base slug" do
    post = Post.create!(title: "!!!", user: @user)
    assert_match(/\Aitem(-\d+)?\z/, post.slug)
  end
end
