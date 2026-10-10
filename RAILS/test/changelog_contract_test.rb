# frozen_string_literal: true

require "minitest/autorun"

class ChangelogContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_changelog_is_single_source_and_publicly_routed
    source = File.read(File.join(ROOT, "__shared/config/changelog.yml"))
    assert_includes source, 'title: "Convergence"'

    %w[brgen amber bsdports].each do |app|
      routes = File.read(File.join(ROOT, app, "config/routes.rb"))
      assert_includes routes, 'get "changelog" => "shared/changelog#show"'
    end
  end

  # The controller loads the file with safe_load, which refuses any class it was
  # not told about. The entries' unquoted `date:` values are Dates, so the file
  # only loads where the controller permits Date; with none permitted /changelog
  # raised on every request.
  def test_the_changelog_loads_with_the_classes_its_controller_permits
    require "yaml"
    require "date"
    controller = File.read(File.join(ROOT, "__shared/app/controllers/shared/changelog_controller.rb"))
    assert_includes controller, "permitted_classes: [Date]"

    data = YAML.safe_load_file(File.join(ROOT, "__shared/config/changelog.yml"), permitted_classes: [Date], aliases: false)
    assert_kind_of Date, data.fetch("entries").first.fetch("date")
  end

  def test_footer_publishes_build_identity
    footer = File.read(File.join(ROOT, "__shared/app/views/shared/_site_legal_footer.html.erb"))
    assert_includes footer, "app_version"
    assert_includes footer, "app_revision"
    assert_includes footer, 'legal.changelog'
  end
end
