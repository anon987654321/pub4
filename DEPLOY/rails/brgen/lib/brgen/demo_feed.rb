# frozen_string_literal: true

module Brgen
  # Prefer credible Bergen demo posts on the flagship feed (not Faker/PerCity noise).
  module DemoFeed
    DEMO_USERNAMES = BergenDemoSeeder::USERS.map(&:last).freeze

    module_function

    def flagship_city?(city)
      city&.domain == "brgen.no"
    end

    def posts_scope(city: ActsAsTenant.current_tenant)
      return Post.none unless flagship_city?(city)

      Post.joins(:user).where(users: { username: DEMO_USERNAMES })
    end

    def available?(city: ActsAsTenant.current_tenant)
      posts_scope(city: city).exists?
    end

    def hot(city: ActsAsTenant.current_tenant, limit: 50)
      posts_scope(city: city).hot.limit(limit)
    end
  end
end