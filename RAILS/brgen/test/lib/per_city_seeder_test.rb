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
# A city's bank must sound like that city. These are the markers the sources
# record, not an impression of them, and they are the half a later cleanup
# pass would flatten first — "Ka gjør dokker" reads like a typo to anyone
# correcting toward bokmål.
# Case-insensitive, and wide enough to be the dialect rather than one phrase
# from it. The first draft read /\beg\b/ case-sensitively and failed the
# Stavanger replies, which open sentences with "Eg" — the instrument, not the
# copy. Each set is several markers and the assertion needs one, so a rewrite
# that keeps the dialect and changes the wording still passes.
DIALECT_MARKERS = {
    # Bergen types bokmål and speaks bergensk — the operator's correction. The
    # pronouns do not survive into writing; the vocabulary with no bokmål
    # equivalent does — plus the idiom "den er brun" and the names only a
    # Brann supporter writes, Bataljonen and Store Stå. A Bergen bank carrying
    # none of these is any Norwegian city.
    "brgen.no" => [ /\bboss(et)?\b/i, /\bsmau(et)?\b/i, /\bbekkalokk/i, /\bkjuagutt\b/i,
                    /\btebrød\b/i, /\bbrun\b/i, /\bBataljonen\b/, /\bStore Stå\b/, /\beg\b/ ],
  "trndheim.no" => [ /\bæ\b/i, /\bitj\b/i, /\bdokker\b/i ],
  "stvanger.no" => [ /\beg\b/i, /\bikkje\b/i, /\bberre\b/i, /\bmykje\b/i, /\båleine\b/i ],
  "oshlo.no" => [ /\bklokka\b/i, /\bsola\b/i, /\bboka\b/i, /\bsyns\b/i ]
}.freeze

test "every city bank is written in that city's dialect" do
  DIALECT_MARKERS.each do |domain, markers|
    bank = Brgen::CityContent.posts_for(domain)
    refute_nil bank, "#{domain} lost its post bank"
      text = bank.flatten.join(" ")
      # Any, not every. A dialect is a set of habits, not a checklist: Oslo copy
      # need not contain klokka AND sola AND boka AND syns to be Oslo copy, and
      # requiring all four made this a word quota that an honest rewrite fails.
      assert markers.any? { |marker| text.match?(marker) },
             "#{domain} no longer sounds like #{domain}"
  end
end

test "no two cities share a post" do
  banks = Brgen::CityContent::POSTS_BY_DOMAIN
  titles = banks.values.flatten(1).map(&:first)
  assert_equal titles.uniq.size, titles.size, "a post is seeded under two cities"
end

# Bergen's own seeder owns brgen.no, so a bank for a domain with no city
# would seed nothing and read as a silent gap rather than a failure.
test "every bank names a domain the registry knows" do
  known = Brgen::DomainRegistry::ENTRIES_BY_DOMAIN.keys
  Brgen::CityContent::POSTS_BY_DOMAIN.each_key do |domain|
    assert_includes known, domain, "#{domain} has a post bank and no registry entry"
  end
end

# A post with no comments renders an empty section under it, which is what
# oshlo, stvanger and trndheim had: only Bergen's own seeder wrote any.
test "every banked post carries replies" do
  Brgen::CityContent::POSTS_BY_DOMAIN.each do |domain, bank|
    bank.each do |title, _content, comments|
      refute_nil comments, "#{domain}: '#{title}' has no comments"
      assert_operator comments.size, :>=, 2, "#{domain}: '#{title}' has only #{comments.size} reply"
    end
  end
end

# A Bergen reply under a Trondheim question is the same defect as a Bergen
# post there. The markers are checked over the replies alone, so a bank whose
# posts are in dialect and whose comments are not still fails.
test "replies are in the same dialect as the post" do
  DIALECT_MARKERS.each do |domain, markers|
    replies = Brgen::CityContent.posts_for(domain).flat_map { |row| row[2] }.join(" ")
    assert markers.any? { |marker| replies.match?(marker) },
           "#{domain} replies do not sound like #{domain}"
  end
end

# Copy is typed, and a homoglyph is invisible in review: two Cyrillic letters
# reached the Stavanger bank as "bilетet" and would have rendered as a broken
# word on a live page.
test "no bank contains a non-Latin homoglyph" do
  text = Brgen::CityContent::POSTS_BY_DOMAIN.values.flatten.join(" ")
  assert_no_match(/[Ѐ-ӿͰ-Ͽ]/, text, "a Cyrillic or Greek character reached the copy")
end

end
