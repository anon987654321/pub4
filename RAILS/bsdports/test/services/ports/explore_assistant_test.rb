# frozen_string_literal: true

require "test_helper"

class PortsExploreAssistantTest < ActiveSupport::TestCase
  setup do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel", description: "devel")
    @maintainer = Maintainer.create!(name: "Ola Nordmann", email: "ola@example.test")
    @port = Port.create!(
      platform:,
      category:,
      maintainer: @maintainer,
      name: "git",
      pkgpath: "devel/git",
      comment: "distributed version control",
      version: "2.45.0"
    )
  end

  test "summarize includes port identity" do
    summary = Ports::ExploreAssistant.summarize(@port)
    assert_includes summary, "git"
    assert_includes summary, "devel/git"
  end

  test "summarize speaks the request locale" do
    summary = I18n.with_locale(:nb) { Ports::ExploreAssistant.summarize(@port) }

    assert_includes summary, I18n.t("ports.explore_assistant.maintainer", name: "Ola Nordmann", locale: :nb)
    assert_includes summary, I18n.t("ports.explore_assistant.no_dependencies", locale: :nb)
    assert_includes summary, I18n.t("ports.explore_assistant.no_advisories", locale: :nb)
  end

  test "a preloaded maintainer is named, not inspected" do
    port = Port.includes(:category, :maintainer).find(@port.id)
    summary = Ports::ExploreAssistant.summarize(port)

    assert_includes summary, "Ola Nordmann"
    assert_not_includes summary, "#<Maintainer"
  end
end
