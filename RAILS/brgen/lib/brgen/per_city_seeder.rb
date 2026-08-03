# frozen_string_literal: true

require "faker"

module Brgen
  class PerCitySeeder
    def self.seed_all!(cities: City.order(:id).to_a, posts_per_city: 8)
      cities.each { |city| new(city, posts_per_city:).seed! }
    end

    def initialize(city, posts_per_city: 8)
      @city = city
      @posts_per_city = posts_per_city
      @entry = DomainRegistry::ENTRIES_BY_DOMAIN[city.domain]
    end

    def seed!
      ActsAsTenant.with_tenant(@city) do
        admin = seed_admin
        communities = seed_communities(admin)
        # with_faker_locale owns both halves of the locale switch: pointing
        # Faker at the city's language, and admitting that locale to
        # I18n.available_locales so Faker can actually reach the data. Setting
        # Faker::Config.locale alone silently produced English names.
        Brgen::CityContent.with_faker_locale(country) do
          users = seed_users
          seed_posts(admin, users, communities)
        end
      end
    end

    private

    def seed_admin
      email = "admin@#{@city.domain}"

      # Email uniqueness is global, but User is tenant-scoped (CityTenantable),
      # and seed! runs inside with_tenant. So a find_or_create_by! here cannot
      # see an admin row that has no city_id — and db/seeds.rb creates exactly
      # one of those ("admin@brgen.no", before it assigns a tenant). The find
      # missed it, the create hit the global uniqueness validation, and the
      # whole db:seed run died with "Email address er allerede i bruk" on every
      # replant after the first.
      existing = ActsAsTenant.without_tenant do
        User.strict_loading(false).find_by(email_address: email)
      end

      if existing
        # Adopt an unassigned admin into the city that owns its domain, but
        # never reassign one that already belongs to a different city.
        existing.update!(city: @city) if existing.city_id.nil?
        return existing
      end

      User.strict_loading(false).create!(
        email_address: email,
        username: "admin_#{@city.slug}",
        password: "password123",
        password_confirmation: "password123",
        city: @city,
        latitude: @city.latitude,
        longitude: @city.longitude
      )
    end

    def country
      @entry&.country || @city.country_code
    end

    def seed_communities(admin)
      Brgen::CityContent.community_slugs_for(country).map do |slug|
        Community.find_or_create_by!(slug: slug, city: @city) do |community|
          community.name = slug.capitalize
          community.description = "#{@city.name} — #{slug}"
          community.user = admin
        end
      end
    end

    def seed_users
      5.times.map do |index|
        # A real-sounding name in the caller's locale (Faker::Config.locale
        # was set for this city in seed!), not a robotic "lsangeles_3" --
        # username is this app's actual display_name, so it's user-visible.
        # first_name+last_name directly (not Faker::Name.name) to avoid the
        # prefixes/suffixes ("Prof.", "Esq.", "III") name sometimes bakes in,
        # which read oddly in a username. The city slug keeps it unique
        # against every other city's users (username uniqueness is global,
        # not per-city) without the name itself needing to carry an index.
        name_slug = "#{Faker::Name.first_name} #{Faker::Name.last_name}".parameterize(separator: "_")
        User.strict_loading(false).find_or_create_by!(
          email_address: "seed_#{@city.slug}_#{index}@#{@city.domain}"
        ) do |user|
          # The city slug keeps names unique across cities, but two of the 5 random
          # Faker names can collide WITHIN a city (no index in the visible name) —
          # a flaky "Username er allerede i bruk" on replant. The index (before the
          # city slug) guarantees within-city uniqueness while the username still
          # ends in _<city.slug> for the global-uniqueness namespacing.
          user.username = "#{name_slug}_#{index + 1}_#{@city.slug}"
          user.password = user.password_confirmation = "password123"
          user.city = @city
          user.latitude = @city.latitude.to_f + rand(-0.05..0.05)
          user.longitude = @city.longitude.to_f + rand(-0.05..0.05)
        end
      end
    end

    def seed_posts(admin, users, communities)
      pool = users + [ admin ]
      # Faker::Lorem is Latin in every locale, so localising Faker did nothing
      # for post bodies. PlausibleContent carries real sentences; Norwegian
      # cities get Norwegian, everywhere else falls back to English.
      norwegian = Brgen::PlausibleContent.norwegian_country?(country)
      @posts_per_city.times do
        Post.create!(
          user: pool.sample,
          city: @city,
          community: communities.sample,
          title: Brgen::PlausibleContent.post_title(@city.name, norwegian: norwegian),
          content: Brgen::PlausibleContent.post_body(norwegian: norwegian)
        )
      end
    end
  end
end
