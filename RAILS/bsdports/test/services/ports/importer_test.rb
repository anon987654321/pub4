# frozen_string_literal: true

require "test_helper"

class Ports::ImporterTest < ActiveSupport::TestCase
  test "imports ports from fixture tree with dependencies" do
    platform = platforms(:openbsd)
    tree_path = Rails.root.join("test/fixtures/ports/openbsd")

    result = Ports::Importer.call(platform:, tree_path:, use_ftp_fallback: false)

    assert_equal 2, result.ports_count
    git = Port.includes(:category).find_by!(platform:, pkgpath: "devel/git")
    gettext = Port.includes(:category).find_by!(platform:, pkgpath: "devel/gettext")

    assert_equal "distributed version control", git.comment
    assert_equal "devel", git.category.slug
    assert_equal 2, git.dependencies.count
    assert git.dependencies.exists?(depends_on: gettext, dep_type: "build")
    assert_equal "succeeded", result.import_run.status
  end
end