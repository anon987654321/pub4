# frozen_string_literal: true

require "test_helper"

# The maintainer index and pages printed every address as name@host, the
# page with a mailto, so the crawlable lists handed out about a thousand.
class MaintainerEmailTest < ActionDispatch::IntegrationTest
  setup do
    @maintainer = Maintainer.create!(name: "Jane Porter", email: "jane@openbsd.org")
  end

  test "the maintainer index does not print a harvestable address" do
    get maintainers_path
    assert_response :success
    assert_not_includes response.body, "jane@openbsd.org"
    shown = I18n.t("maintainers.email_obfuscated", user: "jane", domain: "openbsd.org")
    assert_select "span.maintainer-email", text: shown
  end

  test "the maintainer page has no mailto and no plain address" do
    get maintainer_path(@maintainer)
    assert_response :success
    assert_not_includes response.body, "jane@openbsd.org"
    assert_select "a[href^='mailto:']", count: 0
  end
end
