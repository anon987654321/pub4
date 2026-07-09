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
        users = seed_users
        seed_posts(admin, users, communities)
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

    def seed_communities(admin)
      country = @entry&.country || @city.country_code
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
        User.strict_loading(false).find_or_create_by!(
          email_address: "seed_#{@city.slug}_#{index}@#{@city.domain}"
        ) do |user|
          user.username = "#{@city.slug}_#{index}"
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