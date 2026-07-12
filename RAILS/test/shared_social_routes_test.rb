# frozen_string_literal: true

require "minitest/autorun"

class SharedSocialRoutesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  def test_all_apps_expose_shared_social_endpoints
    social = File.read(File.join(ROOT, "shared/config/routes/social.rb"))
    APPS.each do |app|
      routes = File.read(File.join(ROOT, app, "config/routes.rb"))
      source = routes.include?("shared/config/routes/social.rb") ? "#{routes}\n#{social}" : routes
      assert_match(/notifications/, source, "#{app} missing notifications routes")
      assert_match(/reactions/, source, "#{app} missing reactions routes")
      assert_match(/reports/, source, "#{app} missing reports routes")
    end
  end

  def test_apps_load_shared_social_route_partial
    %w[amber bsdports].each do |app|
      routes = File.read(File.join(ROOT, app, "config/routes.rb"))
      assert_includes routes, "shared/config/routes/social.rb", "#{app} should eval shared social routes"
    end
  end
end
