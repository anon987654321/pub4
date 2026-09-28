# frozen_string_literal: true

require "minitest/autorun"

class ChangelogContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_changelog_is_single_source_and_publicly_routed
    source = File.read(File.join(ROOT, "shared/config/changelog.yml"))
    assert_includes source, 'title: "Convergence"'

    %w[brgen amber bsdports].each do |app|
      routes = File.read(File.join(ROOT, app, "config/routes.rb"))
      assert_includes routes, 'get "changelog" => "shared/changelog#show"'
    end
  end

  def test_footer_publishes_build_identity
    footer = File.read(File.join(ROOT, "shared/app/views/shared/_site_legal_footer.html.erb"))
    assert_includes footer, "app_version"
    assert_includes footer, "app_revision"
    assert_includes footer, 'legal.changelog'
  end
end
