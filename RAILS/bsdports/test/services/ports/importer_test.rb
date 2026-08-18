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

  # The defect that kept bsdports.org empty from launch: with no tree on disk
  # the importer raised before it reached the remote fallback, so the fallback
  # could only ever run when a tree existed AND yielded nothing. /usr/ports is
  # the configured tree_path and neither vm23 nor a dev Mac has one, so that was
  # every run. Asserting reachability, not the fetch itself.
  test "with no local tree it reaches the remote fallback instead of raising there" do
    platform = platforms(:openbsd)
    fetcher = FakeIndexFetcher.new([
      { name: "git", version: "2.49.0", pkgpath: "packages/git", category: "uncategorised" },
    ])

    Ports::Openbsd::PackageIndexFetcher.stub(:new, ->(**) { fetcher }) do
      Ports::Openbsd::PortsTarball.stub(:new, ->(**) { FakeTarball.new }) do
        result = Ports::Importer.call(platform:, tree_path: "/nonexistent/ports", use_ftp_fallback: true)

        assert_equal 1, result.ports_count
        assert_equal "succeeded", result.import_run.status
      end
    end

    assert fetcher.consulted, "importer must consult the remote fallback when there is no tree on disk"
    assert Port.exists?(platform:, pkgpath: "packages/git")
  end

  test "a run that imports nothing fails loudly rather than reporting success" do
    platform = platforms(:openbsd)

    error = assert_raises(RuntimeError) do
      Ports::Importer.call(platform:, tree_path: "/nonexistent/ports", use_ftp_fallback: false)
    end

    assert_match(/no ports imported|remote_fallback/, error.message)
    assert_equal "failed", platform.import_runs.order(:id).last.status
  end

  test "package index rows import with a namespaced pkgpath that cannot collide with a real one" do
    row = Ports::Openbsd::PackageIndexParser.parse_pkgname("git-2.49.0")

    assert_equal "git", row[:name]
    assert_equal "2.49.0", row[:version]
    assert_equal "packages/git", row[:pkgpath]
    refute_equal "devel/git", row[:pkgpath], "synthetic pkgpaths must not shadow ports-tree ones"
  end

  test "package index parser reads the mirror's ls -l listing" do
    line = "-rw-r--r--  1 0  0    83961563 Apr 25 13:24:13 2026 0ad-0.28.0.tgz"
    row = Ports::Openbsd::PackageIndexParser.parse_line(line)

    assert_equal "0ad", row[:name]
    assert_equal "0.28.0", row[:version]
    assert_nil Ports::Openbsd::PackageIndexParser.parse_line("total 2096391")
  end

  test "multi-hyphen stems keep their name" do
    row = Ports::Openbsd::PackageIndexParser.parse_pkgname("p5-Net-SSLeay-1.92")

    assert_equal "p5-Net-SSLeay", row[:name]
    assert_equal "1.92", row[:version]
  end

  # The tarball is guarded on free disk because vm23 has 962 MB free on a /home
  # that is already 95% full. A guard that cannot decline is not a guard.
  test "the ports tarball declines when it is switched off" do
    platform = platforms(:openbsd)
    tarball = Ports::Openbsd::PortsTarball.new(platform:, release: "7.9")

    ENV.delete("BSDPORTS_PORTS_TARBALL")
    assert_match(/not 1/, tarball.decline_reason.to_s)
    assert_nil tarball.with_tree { |_| flunk "must not extract while disabled" }
  end

  class FakeTarball
    def with_tree = nil
    def url = "fake"
  end

  class FakeIndexFetcher
    attr_reader :consulted

    def initialize(entries)
      @entries = entries
      @consulted = false
    end

    def each_entry
      @consulted = true
      @entries
    end

    def release = "7.9"
    def index_url = "https://example.invalid/index.txt"
  end
end
