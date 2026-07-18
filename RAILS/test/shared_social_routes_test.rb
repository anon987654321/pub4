# frozen_string_literal: true

require "minitest/autorun"

class SharedSocialRoutesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FULL_SOCIAL_APPS = %w[amber brgen].freeze

  def test_social_apps_expose_shared_social_endpoints
    social = File.read(File.join(ROOT, "shared/config/routes/social.rb"))
    FULL_SOCIAL_APPS.each do |app|
      routes = File.read(File.join(ROOT, app, "config/routes.rb"))
      source = routes.include?("shared/config/routes/social.rb") ? "#{routes}\n#{social}" : routes
      assert_match(/notifications/, source, "#{app} missing notifications routes")
      assert_match(/reactions/, source, "#{app} missing reactions routes")
      assert_match(/reports/, source, "#{app} missing reports routes")
    end
  end

  def test_social_apps_load_shared_social_route_partial
    FULL_SOCIAL_APPS.each do |app|
      routes = File.read(File.join(ROOT, app, "config/routes.rb"))
      assert_includes routes, "shared/config/routes/social.rb", "#{app} should eval shared social routes"
    end
  end

  def test_bsdports_social_is_opt_in
    routes = File.read(File.join(ROOT, "bsdports", "config/routes.rb"))
    assert_includes routes, "BSDPORTS_SOCIAL"
    assert_includes routes, "shared/config/routes/social.rb"
    # Must not always load social without the flag
    refute_match(/instance_eval.*social\.rb(?!.*BSDPORTS)/m, routes.split("BSDPORTS_SOCIAL").first)
  end
end
