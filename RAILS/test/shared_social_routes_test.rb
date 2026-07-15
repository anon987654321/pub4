# frozen_string_literal: true

require "minitest/autorun"

class SharedSocialRoutesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  # bsdports omits social routes — no notifications/reactions schema (WIRING_NOTES.md).
  SOCIAL_APPS = %w[amber brgen].freeze

  def test_all_apps_expose_shared_social_endpoints
    social = File.read(File.join(ROOT, "shared/config/routes/social.rb"))
    SOCIAL_APPS.each do |app|
      routes = File.read(File.join(ROOT, app, "config/routes.rb"))
      source = routes.include?("shared/config/routes/social.rb") ? "#{routes}\n#{social}" : routes
      assert_match(/notifications/, source, "#{app} missing notifications routes")
      assert_match(/reactions/, source, "#{app} missing reactions routes")
      assert_match(/reports/, source, "#{app} missing reports routes")
    end
  end

  def test_apps_load_shared_social_route_partial
    routes = File.read(File.join(ROOT, "amber", "config/routes.rb"))
    assert_includes routes, "shared/config/routes/social.rb", "amber should eval shared social routes"
  end

  def test_bsdports_omits_social_routes_by_design
    routes = File.read(File.join(ROOT, "bsdports", "config/routes.rb"))
    refute_includes routes, "shared/config/routes/social.rb"
    refute_match(/notifications/, routes)
  end
end
