# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class PortsReviewTest < ActiveSupport::TestCase
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "devel", slug: "devel-review")
    @port = Port.create!(
      platform: @platform,
      category: @category,
      name: "git",
      pkgpath: "devel/git",
      comment: "distributed version control",
      homepage: "https://old.example.test/",
      version: "2.43.0",
      maintainer: "Old Maintainer <old@example.test>"
    )
  end

  test "checks indexed metadata when the source tree is unavailable" do
    result = Ports::Review.call(port: @port, tree_path: "/does/not/exist")

    assert_equal :unavailable, result.source_status
    assert_nil result.source_path
    assert_empty result.issues
  end

  test "finds missing source and weak indexed metadata" do
    @port.update!(homepage: nil, comment: "short")
    result = Ports::Review.call(port: @port, tree_path: "/does/not/exist")

    assert_includes result.issues, :missing_homepage
    assert_includes result.issues, :weak_comment
    assert_equal :unavailable, result.source_status
  end

  test "compares the indexed record with the real Makefile" do
    Dir.mktmpdir do |dir|
      port_dir = File.join(dir, "devel", "git")
      FileUtils.mkdir_p(File.join(port_dir, "files"))
      File.write(File.join(port_dir, "Makefile"), <<~MAKE)
        COMMENT = better source comment
        MAINTAINER = OpenBSD Ports <ports@openbsd.org>
        HOMEPAGE = https://git-scm.com/
        DISTNAME = git-2.44.0
        PERMIT_PACKAGE = Yes
      MAKE
      File.write(File.join(port_dir, "files", "patch-empty"), "")

      result = Ports::Review.call(port: @port, tree_path: dir)

      assert_equal :available, result.source_status
      assert_equal 4, result.mismatches.size
      assert_includes result.issues, :source_comment_mismatch
      assert_includes result.issues, :source_homepage_mismatch
      assert_includes result.issues, :source_maintainer_mismatch
      assert_includes result.issues, :source_version_mismatch
      assert_includes result.issues, :empty_patch
    end
  end

  test "rejects a pkgpath that escapes the configured tree" do
    @port.update!(pkgpath: "../outside")
    Dir.mktmpdir do |dir|
      result = Ports::Review.call(port: @port, tree_path: dir)

      assert_equal :missing_port_directory, result.issues.last
      assert_equal :missing, result.source_status
    end
  end
end
