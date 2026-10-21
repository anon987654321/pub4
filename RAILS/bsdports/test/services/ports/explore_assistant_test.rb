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

  test "summarize includes runtime, build, test and library dependencies" do
    runtime = make_port("runtime-tool")
    build = make_port("build-tool")
    test_port = make_port("test-tool")
    library = make_port("core-library")
    Dependency.create!(port: @port, depends_on: runtime, dep_type: "run")
    Dependency.create!(port: @port, depends_on: build, dep_type: "build")
    Dependency.create!(port: @port, depends_on: test_port, dep_type: "test")
    Dependency.create!(port: @port, depends_on: library, dep_type: "lib")

    summary = Ports::ExploreAssistant.summarize(@port)

    assert_includes summary, "runtime-tool"
    assert_includes summary, "build-tool"
    assert_includes summary, "test-tool"
    assert_includes summary, "core-library"
  end

  test "a preloaded maintainer is named, not inspected" do
    port = Port.includes(:category, :maintainer).find(@port.id)
    summary = Ports::ExploreAssistant.summarize(port)

    assert_includes summary, "Ola Nordmann"
    assert_not_includes summary, "#<Maintainer"
  end
  private

  def make_port(name)
    Port.create!(platform: @port.platform, category: @port.category, name:,
                 pkgpath: "devel/#{name}", version: "1")
  end
end
