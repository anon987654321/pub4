# frozen_string_literal: true

require "test_helper"
# Faker is a gem, not autoloadable, and these tests touch Faker::Config before
# any Brgen constant that requires it — without this the file passed or failed
# depending on whether an earlier test happened to load faker first.
require "faker"

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
  # Faker's locale is now set per city's country for the duration of seeding
  # (Brgen::CityContent.with_faker_locale) so the generated name actually
  # sounds like it belongs to that country.
  test "seeds users with locale-appropriate real names, not robotic slugs" do
    city = City.find_by!(domain: "brgen.no")
    seeder = Brgen::PerCitySeeder.new(city, posts_per_city: 1)
    users = ActsAsTenant.with_tenant(city) do
      Brgen::CityContent.with_faker_locale(city.country_code) do
        seeder.send(:seed_users)
      end
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

  # These are Faker's locale ids, which are mostly region-tagged. An earlier
  # version of this test asserted bare tags ("nb", "de") on the theory that a
  # region tag would raise I18n::InvalidLocale inside a booted app. The tag
  # does raise if you only set Faker::Config.locale — but the bare tag doesn't
  # fail loudly either, it silently yields English data, which is how every
  # city ended up with English-sounding people. with_faker_locale admits the
  # locale to I18n for the duration instead, which is what makes the real
  # Faker locale ids usable.
  test "locale_for returns Faker locale ids that actually carry data" do
    assert_equal "nb-NO", Brgen::CityContent.locale_for("NO")
    assert_equal "nb-NO", Brgen::CityContent.locale_for("IS"), "no Icelandic Faker locale; nearest Nordic stock beats English"
    assert_equal "de-CH", Brgen::CityContent.locale_for("CH")
    assert_equal "sv", Brgen::CityContent.locale_for("SE")
    assert_equal "en-US", Brgen::CityContent.locale_for("ZZ"), "unknown country codes fall back to US, matching community_slugs_for"

    # Every mapped locale must be one Faker ships a data file for, or the
    # switch silently degrades to English again.
    faker_locales = Dir.glob(File.join(Gem.loaded_specs.fetch("faker").gem_dir, "lib/locales/*.yml"))
                       .map { |path| File.basename(path, ".yml") }
    Brgen::CityContent::LOCALE_BY_COUNTRY.each_value do |locale|
      assert_includes faker_locales, locale, "Faker ships no #{locale}.yml, so this mapping would fall back to English"
    end
  end

  test "with_faker_locale yields real localized data and restores I18n state" do
    previous_available = I18n.available_locales
    previous_locale = Faker::Config.locale

    names = Brgen::CityContent.with_faker_locale("NO") do
      assert_includes I18n.available_locales, :"nb-NO", "the locale must be admitted to I18n or Faker can't reach its data"
      5.times.map { Faker::Name.last_name }
    end

    assert_equal 5, names.size
    names.each { |name| assert name.present? }

    assert_equal previous_available, I18n.available_locales, "available_locales must be restored; it is process-global"
    assert_equal previous_locale, Faker::Config.locale
  end

  # The bug this guards: db/seeds.rb creates admin@brgen.no with no city_id,
  # but seed! runs inside with_tenant and User is tenant-scoped, so a scoped
  # find_or_create_by! could not see that row and tripped the global email
  # uniqueness validation -- taking down the whole db:seed run on every replant.
  test "seed_admin adopts an existing city-less admin instead of duplicating it" do
    city = City.find_by!(domain: "brgen.no")
    # Adopt the orphan if one is already there. The precondition this test needs
    # is "a city-less admin exists", not "this test created it" — and db/seeds.rb
    # creates exactly that user, so on the VPS, whose CI seeds before running the
    # suite, the bare create! raised "Email address er allerede i bruk" and the
    # test failed for having its precondition already satisfied. Locally, with an
    # unseeded test database, it passed.
    orphan = ActsAsTenant.without_tenant do
      User.find_by(email_address: "admin@#{city.domain}", city_id: nil) ||
        User.create!(
          email_address: "admin@#{city.domain}",
          username: "preexisting_admin",
          password: "password123",
          password_confirmation: "password123"
        )
    end
    assert_nil orphan.city_id

    seeder = Brgen::PerCitySeeder.new(city, posts_per_city: 1)
    admin = ActsAsTenant.with_tenant(city) { seeder.send(:seed_admin) }

    assert_equal orphan.id, admin.id, "should reuse the existing admin row, not attempt a second one"
    assert_equal city.id, admin.reload.city_id, "an unassigned admin should be adopted into its domain's city"
    assert_equal 1, ActsAsTenant.without_tenant { User.where(email_address: "admin@#{city.domain}").count }
  end
end
