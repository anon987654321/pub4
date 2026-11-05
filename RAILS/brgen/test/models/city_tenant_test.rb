# frozen_string_literal: true

require "test_helper"

class CityTenantTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @cities = %w[brgen.no oshlo.no lsangeles.com cardff.uk frankfrt.de].index_with do |domain|
      City.find_by!(domain:)
    end
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "posts remain isolated across Nordic, US, UK and German tenants" do
    token = SecureRandom.hex(4)
    posts = @cities.each_with_index.to_h do |(domain, city), index|
      post = ActsAsTenant.with_tenant(city) do
        user = User.strict_loading(false).create!(
          email_address: "tenant-#{token}-#{index}@example.com",
          password: "password123",
          username: "tenant_#{token}_#{index}",
          city:
        )
        community = Community.create!(
          slug: "tenant-#{token}-#{index}",
          name: "Tenant #{city.name}",
          user:,
          city:
        )
        Post.create!(
          user:,
          community:,
          city:,
          title: "Tenant-only post #{domain}",
          content: "Private to #{city.name}"
        )
      end
      [ domain, post ]
    end

    @cities.each do |domain, city|
      ActsAsTenant.with_tenant(city) do
        visible = Post.pluck(:title)
        assert_includes visible, posts.fetch(domain).title
        (posts.keys - [ domain ]).each do |other_domain|
          refute_includes visible, posts.fetch(other_domain).title,
                          "#{domain} must not read #{other_domain}"
        end
      end
    end
  end
end
