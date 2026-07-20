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
    seeder = Brgen::PerCitySeeder.new(city, posts_per_city: 1)
    users = ActsAsTenant.with_tenant(city) do
      Faker::Config.locale = Brgen::CityContent.locale_for(city.country_code)
      seeder.send(:seed_users)
    end

    assert_equal 5, users.size
    users.each do |user|
      refute_match(/\A#{city.slug}_\d\z/, user.username, "username should be a real name, not the old city_slug_index pattern")
      assert_match(/_#{city.slug}\z/, user.username, "username should still be namespaced by city for global uniqueness")
      assert user.username.length > (city.slug.length + 4), "username should carry a real name, not just the city slug"
    end
  end

  test "seed! sets the country-appropriate locale during seeding, then restores it" do
    city = City.find_by!(domain: "amstrdam.nl")
    previous_locale = Faker::Config.locale
    locales_seen = []
    original_setter = Faker::Config.method(:locale=)
    Faker::Config.define_singleton_method(:locale=) do |value|
      locales_seen << value
      original_setter.call(value)
    end

    begin
      Brgen::PerCitySeeder.new(city, posts_per_city: 1).seed!
    ensure
      Faker::Config.define_singleton_method(:locale=, original_setter)
    end

    assert_includes locales_seen, "nl", "seed! should set the Dutch locale while seeding amstrdam.nl"
    assert_equal previous_locale, Faker::Config.locale, "locale must be restored so other cities/seeders aren't affected"
  end

  test "restricted to config.i18n.available_locales -- falls back to en outside that set" do
    assert_equal "nb", Brgen::CityContent.locale_for("NO")
    assert_equal "nb", Brgen::CityContent.locale_for("IS"), "no native Faker+Rails locale for Iceland; falls back to Norwegian"
    assert_equal "de", Brgen::CityContent.locale_for("CH")
    assert_equal "en", Brgen::CityContent.locale_for("ZZ"), "unknown country codes fall back to en, matching community_slugs_for's US fallback"
    # Every mapped locale must actually be one Rails will accept, or seed!
    # crashes with I18n::InvalidLocale the moment Faker touches I18n inside
    # a booted app (region variants like "nb-NO" do NOT satisfy this even
    # though Faker supports them standalone -- see city_content.rb's comment).
    Brgen::CityContent::LOCALE_BY_COUNTRY.each_value do |locale|
      assert_includes I18n.available_locales.map(&:to_s), locale,
        "#{locale} must be in config.i18n.available_locales or Faker::Config.locale= raises inside Rails"
    end
  end
end
