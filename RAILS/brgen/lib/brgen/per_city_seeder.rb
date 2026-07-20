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
        # Faker::Config.locale is process-global, not scoped to this block --
        # every city in a seed_all! run shares it, so it must be restored
        # afterward or the next city inherits whatever locale this one set.
        previous_locale = Faker::Config.locale
        Faker::Config.locale = Brgen::CityContent.locale_for(country)
        users = seed_users
        seed_posts(admin, users, communities)
      ensure
        Faker::Config.locale = previous_locale
      end
    end

    private

    def seed_admin
      email = "admin@#{@city.domain}"
      User.strict_loading(false).find_or_create_by!(email_address: email) do |user|
        user.username = "admin_#{@city.slug}"
        user.password = user.password_confirmation = "password123"
        user.city = @city
        user.latitude = @city.latitude
        user.longitude = @city.longitude
      end
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
          user.username = "#{name_slug}_#{@city.slug}"
          user.password = user.password_confirmation = "password123"
          user.city = @city
          user.latitude = @city.latitude.to_f + rand(-0.05..0.05)
          user.longitude = @city.longitude.to_f + rand(-0.05..0.05)
        end
      end
    end

    def seed_posts(admin, users, communities)
      pool = users + [ admin ]
      @posts_per_city.times do
        Post.create!(
          user: pool.sample,
          city: @city,
          community: communities.sample,
          title: Faker::Lorem.sentence(word_count: 5),
          content: "#{@city.name}: #{Faker::Lorem.paragraph(sentence_count: 3)}"
        )
      end
    end
  end
end
