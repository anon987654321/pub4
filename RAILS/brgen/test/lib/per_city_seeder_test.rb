# frozen_string_literal: true

require "test_helper"

class PerCitySeederTest < ActiveSupport::TestCase
  parallelize(workers: 1)

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # Regression: seeded users used to get robotic usernames like "lsangeles_3"
  # with no real name anywhere -- the opposite of "realistic local users."
  # Faker::Config.locale is now set per city's country (Brgen::CityContent
  # .locale_for) so the generated name actually sounds like it belongs to
  # that country, not a generic Faker default.
  test "seeds users with locale-appropriate real names, not robotic slugs" do
    city = City.find_by!(domain: "brgen.no")
    users = ActsAsTenant.with_tenant(city) { Brgen::PerCitySeeder.new(city, posts_per_city: 1).seed_users }

    assert_equal 5, users.size
    users.each do |user|
      refute_match(/\A#{city.slug}_\d\z/, user.username, "username should be a real name, not the old city_slug_index pattern")
      assert_match(/_#{city.slug}\z/, user.username, "username should still be namespaced by city for global uniqueness")
      assert user.username.length > (city.slug.length + 4), "username should carry a real name, not just the city slug"
    end
  end

  test "uses the country-appropriate Faker locale while seeding, then restores it" do
    city = City.find_by!(domain: "amstrdam.nl")
    previous_locale = Faker::Config.locale
    seen_locale = nil

    ActsAsTenant.with_tenant(city) do
      seeder = Brgen::PerCitySeeder.new(city, posts_per_city: 1)
      seeder.send(:seed_admin)
      seeder.seed_users
      seen_locale = Faker::Config.locale
    end

    assert_equal "nl", seen_locale
    assert_equal previous_locale, Faker::Config.locale, "locale must be restored so other cities/seeders aren't affected"
  end

  test "falls back to a real Faker locale for countries with no native one" do
    assert_equal "nb-NO", Brgen::CityContent.locale_for("IS")
    assert_equal "de-CH", Brgen::CityContent.locale_for("LI")
    assert_equal "en-US", Brgen::CityContent.locale_for("ZZ"), "unknown country codes fall back to US, matching community_slugs_for"
  end
end
