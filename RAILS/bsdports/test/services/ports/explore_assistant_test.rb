# frozen_string_literal: true

require "test_helper"

class PortsExploreAssistantTest < ActiveSupport::TestCase
  test "summarize includes port identity" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel", description: "devel")
    port = Port.create!(
      platform:,
      category:,
      name: "git",
      pkgpath: "devel/git",
      comment: "distributed version control",
      version: "2.45.0"
    )

    summary = Ports::ExploreAssistant.summarize(port)
    assert_includes summary, "git"
    assert_includes summary, "devel/git"
  end
end
